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
    @State private var loading = true
    @State private var loadID = UUID()
    private var signature: String {
        ExportPreviewFingerprint.signature(input: input, chapters: chapters, profile: profile, pdf: pdf)
    }
    var body: some View {
        ZStack {
            if let error { ContentUnavailableView("Vorschau nicht verfügbar", systemImage: "doc.badge.exclamationmark", description: Text(error)) }
            else if let data { ExportPDFPreview(data: data) }
            else if let html {
                ReadOnlyHTML(html: html, error: $error, loading: $loading, loadID: loadID, currentLoadID: $loadID)
                    .id(loadID)
                    .overlay {
                        if loading {
                            ProgressView("Vorschau wird geladen …")
                                .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
            }
            else { ProgressView(pdf ? "PDF wird gesetzt …" : "Vorschau wird gesetzt …") }
        }.task(id: signature) {
            let log = Logger(subsystem: "com.mobilebox.Skriptum", category: "ExportPreview")
            log.notice("Preview task started, PDF: \(pdf)")
            loadID = UUID(); loading = true; data = nil; html = nil; error = nil
            do {
                try await Task.sleep(for: .milliseconds(180))
                let capturedInput = input, capturedChapters = chapters, capturedProfile = profile
                if pdf {
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
                html = rendered
            } catch is CancellationError { log.notice("Preview task cancelled") } catch { log.notice("Preview task failed, cancelled: \(Task.isCancelled)"); if !Task.isCancelled { self.error = exportMessage(error) } }
        }
    }
}

#if canImport(UIKit)
private struct ExportPDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data); return view
    }
    func updateUIView(_ view: PDFView, context: Context) { view.document = PDFDocument(data: data); view.autoScales = true }
}

#else
private struct ExportPDFPreview: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data); return view
    }
    func updateNSView(_ view: PDFView, context: Context) { view.document = PDFDocument(data: data); view.autoScales = true }
}
#endif
