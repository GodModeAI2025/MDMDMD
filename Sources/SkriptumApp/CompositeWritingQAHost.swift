#if DEBUG
import SwiftUI
import CryptoKit
import ImageIO
import CoreGraphics
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct CompositeWritingQAHost: View {
    @State private var library: WritingLibrary?
    @State private var original: Page?
    @State private var showingEditor = false
    @State private var exportReview: ExportReview?
    private struct ExportReview: Identifiable {
        let id = UUID()
        let page: WritingPage
        let assets: [String: ExportAsset]
        var chapters: [ExportInput] = []
    }
    @State private var focus = false
    @State private var report = ""
    var body: some View {
        NavigationStack {
            List {
                Text("Neue temporäre Manuskriptbibliothek; kein iCloud- oder KI-Zugang.")
                if library != nil {
                    Button("Manuskript öffnen") { showingEditor = true }
                    Button("Gespeicherte Fassung prüfen", action: inspect)
                    if ProcessInfo.processInfo.arguments.contains("--scriptum-markdown-package-ui-qa") {
                        Button("Kapitelvorschau prüfen") {
                            guard var page = library?.pages.first else { return }
                            page.title = "Kapitelvorschau"
                            page.markdown = ""
                            exportReview = ExportReview(page: page, assets: [:], chapters: [
                                ExportInput(title: "Erstes Kapitel", markdown: "# Erstes Kapitel\n\nERSTER-QUELLTEXT 🦊\n"),
                                ExportInput(title: "Zweites Kapitel", markdown: "# Zweites Kapitel\n\nZWEITER-QUELLTEXT **unverändert**\n")
                            ])
                        }
                        Button("Export mit Bildern prüfen") {
                            do {
                                guard let library, let page = library.pages.first, let store = library.store else { return }
                                var assets: [String: ExportAsset] = [:]
                                for asset in page.attachments ?? [] {
                                    assets[asset.relativePath] = ExportAsset(data: try store.attachmentData(asset), mediaType: asset.mediaType)
                                }
                                exportReview = ExportReview(page: page, assets: assets)
                            } catch { report = error.localizedDescription }
                        }
                    }
                }
                Text(report).textSelection(.enabled)
            }.navigationTitle("Manuskriptprüfung")
                .sheet(isPresented: $showingEditor) {
                    if let library, let page = library.pages.first {
                        if ProcessInfo.processInfo.arguments.contains("--scriptum-owner-foreground-ui-qa") {
                            WritingWorkspace(library: library, closeLibrary: { showingEditor = false }, initialPageID: page.id)
                        } else {
                        NavigationStack {
                            PageWritingView(page: page, library: library, focus: $focus, createSubpage: {})
                                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Prüfung schließen") { print("QA_EDITOR_CLOSE_BUTTON"); showingEditor = false } } }
                        }
                        }
                    }
                }
                .sheet(item: $exportReview) { value in ExportOptionsSheet(page: value.page, assets: value.assets, chapters: value.chapters) }
                .onChange(of: showingEditor) { previous, current in print("QA_EDITOR_PRESENTATION \(previous) -> \(current)") }
                .task {
                    guard library == nil else { return }
                    do {
                        let token = UUID().uuidString
                        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumCompositeWritingUIQA-" + token)
                        let documents = root.appendingPathComponent("Documents")
                        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
                        let space = try store.createSpace(title: "Manuskriptprüfung")
                        var text = "# Kapitel Eins\r\n\r\nFließtext mit **Fettdruck**, *Kursivschrift*, e\u{301} und 🦊.\r\n\r\n## Zweiter Abschnitt\r\n\r\nWeiterer Fließtext bleibt in normaler Größe.\r\n\r\n```swift\r\nlet code = 42\r\n```\r\n"
                        if ProcessInfo.processInfo.arguments.contains("--scriptum-composite-large-ui-qa") {
                            text += String(repeating: "\r\nAbsatz des langen Manuskripts: Quellen, Gedanken und eine präzise Frage. 🦊\r\n", count: 8000)
                        }
                        let tools = ProcessInfo.processInfo.arguments.contains("--scriptum-tool-writing-ui-qa")
                        let blocks = tools ? [Block(markdown: "Text für Werkzeuge.\n\n"), Block(markdown: "| Name | Wert |\n| --- | --- |\n| Quelle | 1 |\n")] : [Block(markdown: text)]
                        if tools { text = blocks.map(\.markdown).joined() }
                        let created = try store.createPage(spaceID: space.id, title: "Mehrteiliger Import", markdown: text)
                        try store.setBlocks(pageID: created.id, blocks: blocks, baseRevision: created.revision)
                        guard let single = store.snapshot.pages.first(where: { $0.id == created.id }), single.blocks.count == blocks.count,
                              single.markdown.utf8.elementsEqual(text.utf8) else { throw CocoaError(.fileReadCorruptFile) }
                        if (ProcessInfo.processInfo.arguments.contains("--scriptum-image-preview-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-markdown-package-ui-qa")) {
                            let data = try previewImage()
                            let image = try store.addAttachment(pageID: single.id, data: data, mediaType: "image/png", filename: "Synthetic.png", baseRevision: single.revision)
                            guard let attached = store.snapshot.pages.first(where: { $0.id == single.id }) else { return }
                            let imageBlocks = [Block(markdown: "# Bildvorschau\n\n"),
                                Block(markdown: "![Synthetische Bildvorschau](\(image.relativePath))\n\n"),
                                Block(markdown: "Text nach dem Bild.\n\n")]
                            try store.setBlocks(pageID: attached.id, blocks: imageBlocks, baseRevision: attached.revision)
                            original = store.snapshot.pages.first(where: { $0.id == single.id })
                        } else { original = single }
                        guard let preferences = UserDefaults(suiteName: "Scriptum.CompositeWritingQA." + token) else { return }
                        library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
                        if ProcessInfo.processInfo.arguments.contains("--scriptum-owner-foreground-ui-qa"), let library {
                            library.iCloudSession = ICloudLibrarySession(library: library)
                            print("OWNER_FOREGROUND_QA initialized status=notConfigured directory=\(root.path)")
                        }
                        inspect()
                    } catch { report = error.localizedDescription }
                }
        }
    }
    private func previewImage() throws -> Data {
        guard let context = CGContext(data: nil, width: 3200, height: 1800, bitsPerComponent: 8,
            bytesPerRow: 3200 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1800))
        context.setFillColor(CGColor(red: 0.85, green: 0.6, blue: 0.15, alpha: 1))
        context.fill(CGRect(x: 1600, y: 0, width: 1600, height: 1800))
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
    private func inspect() {
        do {
            guard let library, let store = library.store, let original,
                  let page = try LibraryStore(directory: store.directory).snapshot.pages.first else { return }
            let exact = page.markdown.utf8.elementsEqual(original.markdown.utf8)
            let ids = page.blocks.map(\.id) == original.blocks.map(\.id)
            report = "Gespeicherter Schluss: \(String(page.markdown.suffix(80)))\nGespeicherte Blöcke: \(page.blocks.count)\nUrsprüngliche Block-IDs: \(ids ? "unverändert" : "geändert")\nOriginalbytes: \(exact ? "unverändert" : "bearbeitet")\nUTF-8-Bytes: \(page.markdown.utf8.count)\nSHA256: \(SHA256.hash(data: Data(page.markdown.utf8)).map { String(format: "%02x", $0) }.joined())"
            if (ProcessInfo.processInfo.arguments.contains("--scriptum-image-preview-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-markdown-package-ui-qa")), let attachment = page.attachments?.first {
                let bytes = try store.attachmentData(attachment)
                report += "\nOriginalbild unverändert: \(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == attachment.sha256)\nBildbytes: \(bytes.count)"
            }
            if ProcessInfo.processInfo.arguments.contains("--scriptum-tool-writing-ui-qa") {
                report += "\nSeitenregeln: \(page.assistantRules ?? "")\nGespeicherter Text: \(page.markdown)\nWiederherstellungen: \(library.recoveries.count)"
            }
        } catch { report = error.localizedDescription }
    }
}
#endif
