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
    private struct Revision: Equatable {
        let title: String; let markdown: String; let assets: String; let theme: ExportTheme?
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.title.utf8.elementsEqual(rhs.title.utf8) && lhs.markdown.utf8.elementsEqual(rhs.markdown.utf8) && lhs.assets == rhs.assets && lhs.theme == rhs.theme
        }
    }
    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Vorschau nicht verfügbar", systemImage: "doc.badge.exclamationmark", description: Text(error))
            } else if let html {
                ReadOnlyHTML(html: html, error: $error)
            } else {
                ProgressView("Vorschau wird gesetzt …")
            }
        }
        .task(id: Revision(title: title, markdown: markdown, assets: assets.keys.sorted().map { $0 + ":" + SHA256.hash(data: assets[$0]!.data).map { String(format: "%02x", $0) }.joined() }.joined(separator: "|"), theme: theme)) {
            html = nil; error = nil
            let input = ExportInput(title: title, markdown: markdown, assets: assets, theme: theme)
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ExportEngine.renderHTML(input)
                }.value
                try Task.checkCancellation()
                guard let rendered = String(data: output.data, encoding: .utf8) else { throw ExportUIError.invalidHTML }
                html = rendered
            } catch is CancellationError {} catch { self.error = exportMessage(error) }
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
    func makeCoordinator() -> Coordinator { Coordinator(error: $error) }
    func makeUIView(context: Context) -> WKWebView {
        let view = safeExportWebView()
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard !context.coordinator.html.utf8.elementsEqual(html.utf8) else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        var error: Binding<String?>
        init(error: Binding<String?>) { self.error = error }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(allowedExportNavigation(action) ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { error.wrappedValue = exportMessage(failure) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { error.wrappedValue = exportMessage(failure) }
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
