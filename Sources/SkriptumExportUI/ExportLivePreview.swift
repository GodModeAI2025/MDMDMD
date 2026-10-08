import SwiftUI
import PDFKit
import WebKit
import CryptoKit
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
        var hash = SHA256()
        func append(_ value: Data) { hash.update(data: Data("\(value.count):".utf8)); hash.update(data: value) }
        for value in [input.title, input.markdown, input.author, input.language, profile.rawValue, String(pdf)] { append(Data(value.utf8)) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        append((try? encoder.encode(input.theme)) ?? Data())
        for chapter in chapters {
            append(Data(chapter.title.utf8)); append(Data(chapter.markdown.utf8))
            for path in chapter.assets.keys.sorted() { append(Data(path.utf8)); append(chapter.assets[path]!.data) }
        }
        for path in input.assets.keys.sorted() { append(Data(path.utf8)); append(input.assets[path]!.data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
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
                let artifact = try await Task.detached(priority: .userInitiated) {
                    if capturedChapters.isEmpty { return try ExportEngine.export(capturedInput, format: .html, profile: capturedProfile) }
                    return try ExportEngine.exportManuscript(title: capturedInput.title, chapters: capturedChapters, author: capturedInput.author, language: capturedInput.language, format: .html, profile: capturedProfile, theme: capturedInput.theme)
                }.value
                log.notice("Preview HTML rendering completed")
                try Task.checkCancellation()
                guard let rendered = String(data: artifact.data, encoding: .utf8) else { throw ExportUIError.invalidHTML }
                if pdf {
                    let renderedPDF = try await PaginatedPDF().render(html: rendered, title: input.title, author: input.author, profile: profile, theme: input.theme)
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
