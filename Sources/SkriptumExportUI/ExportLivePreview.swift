import SwiftUI
import PDFKit
import WebKit
import OSLog
#if canImport(SkriptumExport)
import SkriptumExport
#endif

struct ExportLivePreview: View {
    let input: ExportInput
    let chapters: [ExportInput]
    let profile: ExportProfile
    let pdf: Bool
    @State private var data: Data?
    @State private var html: String?
    @State private var error: String?
    private var signature: String {
        ExportPreviewFingerprint.signature(input: input, chapters: chapters, profile: profile, pdf: pdf)
    }
    var body: some View {
        ZStack {
            if let error { ContentUnavailableView("Vorschau nicht verfügbar", systemImage: "doc.badge.exclamationmark", description: Text(error)) }
            else if let data { ExportPDFPreview(data: data) }
            else if let html { ReadOnlyHTML(html: html, error: $error) }
            else { ProgressView(pdf ? "PDF wird gesetzt …" : "Vorschau wird gesetzt …") }
        }.task(id: signature) {
            let log = Logger(subsystem: "com.mobilebox.Skriptum", category: "ExportPreview")
            log.notice("Preview task started, PDF: \(pdf)")
            data = nil; html = nil; error = nil
            do {
                try await Task.sleep(for: .milliseconds(180))
                let capturedInput = input, capturedChapters = chapters, capturedProfile = profile
                if pdf && ExportPDFRoute.usesSemanticQA {
                    let artifact = try await ExportPDFRoute.render(capturedInput, chapters: capturedChapters, profile: capturedProfile)
                    try Task.checkCancellation()
                    data = artifact.data
                    log.notice("Native PDF preview completed")
                    return
                }
                let artifact = try await ExportWorker.run {
                    if capturedChapters.isEmpty { return try ExportEngine.export(capturedInput, format: .html, profile: capturedProfile) }
                    return try ExportEngine.exportManuscript(title: capturedInput.title, chapters: capturedChapters, author: capturedInput.author, language: capturedInput.language, format: .html, profile: capturedProfile, theme: capturedInput.theme)
                }
                log.notice("Preview HTML rendering completed")
                try Task.checkCancellation()
                guard let rendered = String(data: artifact.data, encoding: .utf8) else { throw ExportUIError.invalidHTML }
                if pdf {
                    let renderedPDF = try await PaginatedPDF().render(html: rendered, title: capturedInput.title, author: capturedInput.author, profile: capturedProfile, theme: capturedInput.theme)
                    try Task.checkCancellation(); data = renderedPDF
                    log.notice("Preview PDF completed")
                } else { html = rendered }
            } catch is CancellationError { log.notice("Preview task cancelled") } catch { log.notice("Preview task failed, cancelled: \(Task.isCancelled)"); if !Task.isCancelled { self.error = exportMessage(error) } }
        }
    }
}

private struct ExportPDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data); return view
    }
    func updateUIView(_ view: PDFView, context: Context) { view.document = PDFDocument(data: data); view.autoScales = true }
}
