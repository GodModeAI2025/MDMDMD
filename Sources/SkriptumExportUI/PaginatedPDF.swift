import UIKit
import WebKit
#if canImport(SkriptumExport)
import SkriptumExport
#endif

/// UIKit owns paper geometry and margins for the selected theme.
@MainActor final class ScriptumPrintRenderer: UIPrintPageRenderer {
    private let paper: CGRect
    private let margin: CGFloat
    init(profile: ExportProfile, theme: ExportTheme? = nil) {
        paper = theme?.paperSize == .letter ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        margin = theme.map { CGFloat($0.marginsMM * 72 / 25.4) } ?? (profile == .manuscript ? 70.87 : 56.69)
        super.init()
    }
    override var paperRect: CGRect { paper }
    override var printableRect: CGRect { paper.insetBy(dx: margin, dy: margin) }
}

@MainActor final class PaginatedPDF: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    func render(html: String, title: String, author: String, profile: ExportProfile, theme: ExportTheme? = nil) async throws -> Data {
        try Task.checkCancellation()
        try theme?.validate()
        guard html.utf8.count <= 50_000_000 else { throw ExportUIError.documentTooLarge }
        let view = safeExportWebView()
        let renderer = ScriptumPrintRenderer(profile: profile, theme: theme)
        view.frame = CGRect(origin: .zero, size: renderer.printableRect.size)
        view.navigationDelegate = self
        webView = view
        defer { timeout?.cancel(); timeout = nil; view.stopLoading(); view.navigationDelegate = nil; webView = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (pending: CheckedContinuation<Void, Error>) in
            continuation = pending
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.finish(.failure(ExportUIError.layoutTimeout))
            }
                if Task.isCancelled { finish(.failure(CancellationError())) }
                else { view.loadHTMLString(pdfLayoutHTML(html, theme: theme ?? .preset(for: profile)), baseURL: nil) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.webView?.stopLoading()
                self?.finish(.failure(CancellationError()))
            }
        }
        try Task.checkCancellation()
        view.layoutIfNeeded()
        renderer.addPrintFormatter(view.viewPrintFormatter(), startingAtPageAt: 0)
        let count = renderer.numberOfPages
        guard (1...3000).contains(count) else { throw ExportUIError.invalidPageCount(count) }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: count))
        // Stream to disk so long books do not accumulate thousands of page buffers.
        let destination = URL.temporaryDirectory.appending(path: "Scriptum-PDF-" + UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: destination) }
        var box = renderer.paperRect
        let metadata: [String: Any] = [kCGPDFContextTitle as String: title, kCGPDFContextAuthor as String: author, kCGPDFContextCreator as String: "Scriptum · \(profile.rawValue)"]
        guard let context = CGContext(destination as CFURL, mediaBox: &box, metadata as CFDictionary) else { throw ExportUIError.pdfContext }
        var closed = false
        defer { if !closed { context.closePDF() } }
        for index in 0..<count {
            try Task.checkCancellation()
            autoreleasepool {
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: 0, y: box.height)
                context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context)
                renderer.drawPage(at: index, in: renderer.paperRect)
                UIGraphicsPopContext()
                context.restoreGState()
                context.endPDFPage()
            }
            if index % 8 == 0 {
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 200_000_000 else { throw ExportUIError.documentTooLarge }
            }
            await Task.yield() // Makes the cancel action available while drawing a long book.
        }
        context.closePDF(); closed = true
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 200_000_000 else { throw ExportUIError.documentTooLarge }
        return try Data(contentsOf: destination, options: .mappedIfSafe)
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let pending = continuation else { return }
        continuation = nil; timeout?.cancel(); pending.resume(with: result)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // didFinish includes subresource loading; a subsequent run-loop pass settles native layout.
        Task { @MainActor [weak self] in
            await Task.yield()
            webView.layoutIfNeeded()
            self?.finish(.success(()))
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(allowedExportNavigation(action) ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
}

/// WK's UIKit print formatter maps a CSS pixel to a PDF point. CSS `pt`
/// would therefore enlarge a 14-point theme to 18.67 PDF points. Remove
/// screen-reader padding and CSS page margins; UIKit supplies them once.
private func pdfLayoutHTML(_ html: String, theme: ExportTheme) -> String {
    let override = "<style>@page{margin:0!important}html{font-size:\(theme.bodySizePoints)px!important}html,body{margin:0!important;padding:0!important;max-width:none!important;width:auto!important}body{font-size:\(theme.bodySizePoints)px!important}p{margin-bottom:\(theme.paragraphSpacingPoints)px!important}</style>"
    guard let end = html.range(of: "</head>") else { return html }
    var result = html
    result.insert(contentsOf: override, at: end.lowerBound)
    return result
}
