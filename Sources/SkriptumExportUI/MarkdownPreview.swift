import SwiftUI
import WebKit
import CryptoKit
#if canImport(SkriptumExport)
import SkriptumExport
#endif

/// Uses precisely the HTML export renderer, with ephemeral storage and no script execution.
struct MarkdownPreview: View {
    let title: String
    let markdown: String
    var assets: [String: ExportAsset] = [:]
    var theme: ExportTheme? = nil
    @State private var html: String?
    @State private var error: String?
    @State private var loading = true
    @State private var loadID = UUID()
    private struct Revision: Equatable {
        let title: String; let markdown: String; let assets: String; let theme: ExportTheme?
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.title.utf8.elementsEqual(rhs.title.utf8) && lhs.markdown.utf8.elementsEqual(rhs.markdown.utf8) && lhs.assets == rhs.assets && lhs.theme == rhs.theme
        }
    }
    var body: some View {
        ZStack {
            if let error {
                ContentUnavailableView("Vorschau nicht verfügbar", systemImage: "doc.badge.exclamationmark", description: Text(error))
            } else if let html {
                ReadOnlyHTML(html: html, error: $error, loading: $loading, loadID: loadID, currentLoadID: $loadID)
                    .id(loadID)
                    .overlay {
                        if loading {
                            ProgressView("Vorschau wird geladen …")
                                .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
            } else {
                ProgressView("Vorschau wird gesetzt …")
            }
        }
        .task(id: Revision(title: title, markdown: markdown, assets: assets.keys.sorted().map { $0 + ":" + SHA256.hash(data: assets[$0]!.data).map { String(format: "%02x", $0) }.joined() }.joined(separator: "|"), theme: theme)) {
            loadID = UUID(); loading = true; html = nil; error = nil
            let input = ExportInput(title: title, markdown: markdown, assets: assets, theme: theme)
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ExportEngine.renderHTML(input)
                }.value
                try Task.checkCancellation()
                guard let rendered = String(data: output.data, encoding: .utf8) else { throw ExportUIError.invalidHTML }
                html = rendered
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = exportMessage(error) } }
        }
    }
}

@MainActor func safeExportWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.isInspectable = false
    view.allowsLinkPreview = false
    return view
}

struct ReadOnlyHTML: UIViewRepresentable {
    let html: String
    @Binding var error: String?
    @Binding var loading: Bool
    let loadID: UUID
    @Binding var currentLoadID: UUID
    func makeCoordinator() -> Coordinator { Coordinator(error: $error, loading: $loading, loadID: loadID, currentLoadID: $currentLoadID) }
    func makeUIView(context: Context) -> WKWebView {
        let view = safeExportWebView()
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard !context.coordinator.html.utf8.elementsEqual(html.utf8) else { return }
        context.coordinator.html = html
        context.coordinator.beginLoad()
        view.loadHTMLString(html, baseURL: nil)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.cancelLoad(); view.stopLoading(); view.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        var error: Binding<String?>
        let loading: Binding<Bool>
        let loadID: UUID
        let currentLoadID: Binding<UUID>
        private var timeout: Task<Void, Never>?
        private var active = true
        init(error: Binding<String?>, loading: Binding<Bool>, loadID: UUID, currentLoadID: Binding<UUID>) {
            self.error = error; self.loading = loading; self.loadID = loadID; self.currentLoadID = currentLoadID
        }
        deinit { timeout?.cancel() }
        private var isCurrent: Bool { active && currentLoadID.wrappedValue == loadID }
        func beginLoad() {
            timeout?.cancel()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.isCurrent, !Task.isCancelled, self.loading.wrappedValue else { return }
                self.finish(error: "Die Vorschau konnte nicht rechtzeitig geladen werden. Bitte erneut öffnen.")
            }
        }
        func cancelLoad() { active = false; timeout?.cancel(); timeout = nil }
        private func finish(error message: String? = nil) {
            guard isCurrent else { return }
            timeout?.cancel(); timeout = nil
            if let message { error.wrappedValue = message }
            loading.wrappedValue = false
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(allowedExportNavigation(action) ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { finish(error: exportMessage(failure)) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { finish(error: exportMessage(failure)) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(error: "Die Vorschau wurde unterbrochen. Bitte erneut öffnen.") }
    }
}

enum ExportUIError: LocalizedError {
    case invalidHTML, layoutTimeout, invalidPageCount(Int), documentTooLarge, pdfContext
    var errorDescription: String? {
        switch self {
        case .invalidHTML: "Der Renderer hat kein gültiges UTF-8-HTML geliefert."
        case .documentTooLarge: "Das Dokument überschreitet die sichere Exportgröße (50 MB HTML oder 200 MB PDF)."
        case .pdfContext: "Der PDF-Schreibkontext konnte nicht geöffnet werden."
        case .layoutTimeout: "Das PDF-Layout konnte innerhalb von 30 Sekunden nicht abgeschlossen werden."
        case .invalidPageCount(let count): "PDF-Export abgebrochen: \(count) Seiten liegen außerhalb des zulässigen Bereichs (1–3000)."
        }
    }
}
func exportMessage(_ error: Error) -> String {
    if let error = error as? ExportError {
        switch error {
        case .missingAsset(let path): return "Das Bild „\(path)“ fehlt. Diese Bibliotheksseite enthält noch keine eingebundenen Ordner-Assets. Öffnen Sie das Dokument mit seinen Bildern oder entfernen Sie den Bildverweis."
        default: return "Export nicht möglich: \(String(describing: error))"
        }
    }
    return error.localizedDescription
}

@MainActor func allowedExportNavigation(_ action: WKNavigationAction) -> Bool {
    guard let url = action.request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "about", components.path == "blank", components.query == nil else { return false }
    return (action.navigationType == .other && components.fragment == nil) ||
        (action.navigationType == .linkActivated && components.fragment != nil)
}
