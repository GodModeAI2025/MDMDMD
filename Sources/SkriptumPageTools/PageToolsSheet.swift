import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import CoreTransferable

private struct ImportedPageImage: Transferable, Sendable {
    let data: Data
    let filename: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try readBoundedImage(received.file)
        }
    }
}

private func readBoundedImage(_ url: URL) throws -> ImportedPageImage {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= MediaValidation.maximumBytes else { throw LibraryError.invalidAttachment }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while let chunk = try handle.read(upToCount: min(64 * 1024, MediaValidation.maximumBytes + 1 - data.count)), !chunk.isEmpty {
        data.append(chunk)
        guard data.count <= MediaValidation.maximumBytes else { throw LibraryError.invalidAttachment }
    }
    return ImportedPageImage(data: data, filename: url.lastPathComponent)
}

struct PageToolsSheet: View {
    @State var page: WritingPage
    let library: WritingLibrary
    let updated: (WritingPage) -> Void
    let performMutation: PageToolMutation
    @State private var rules: String
    @State private var prompts: [ReusablePrompt]
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(page: WritingPage, library: WritingLibrary, updated: @escaping (WritingPage) -> Void, performMutation: @escaping PageToolMutation = { $0() }) {
        _page = State(initialValue: page); self.library = library; self.updated = updated
        self.performMutation = performMutation
        _rules = State(initialValue: page.assistantRules ?? ""); _prompts = State(initialValue: page.reusablePrompts ?? [])
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Anweisungen für den Assistenten") {
                    TextEditor(text: $rules).frame(minHeight: 140)
                    Text("Diese Regeln werden nur für bewusst gestartete KI-Aufträge dieser Seite verwendet.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Wiederverwendbare Prompts") {
                    ForEach($prompts) { $prompt in
                        VStack(alignment: .leading) {
                            TextField("Titel", text: $prompt.title)
                            TextField("Auftrag", text: $prompt.text, axis: .vertical).lineLimit(2...6)
                        }
                    }.onDelete { prompts.remove(atOffsets: $0) }
                    Button("Prompt hinzufügen", systemImage: "plus") { prompts.append(ReusablePrompt(title: "Neuer Prompt", text: "")) }
                }
                Section("Bilder") {
                    ForEach(page.attachments ?? []) { image in
                        Label(image.filename, systemImage: "photo").font(.callout)
                    }
                    PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .compatible) { Label("Bild aus Fotos", systemImage: "photo.on.rectangle") }.disabled(busy)
                    Button("Bilddatei einfügen", systemImage: "paperclip") { importing = true }.disabled(busy)
                    if busy { ProgressView("Bild wird gesichert …") }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("Seitenwerkzeuge")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Sichern") {
                        if let saved = performMutation({ library.savePageTools(pageID: page.id, baseRevision: page.revision, rules: rules, prompts: prompts) }) { updated(saved); dismiss() }
                        else { error = library.saveError }
                    }.disabled(busy) }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg]) { result in
                    do {
                        let url = try result.get(); busy = true
                        Task {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() }; busy = false }
                            do {
                                let image = try await Task.detached(priority: .userInitiated) { try readBoundedImage(url) }.value
                                insert(image.data, filename: image.filename)
                            } catch { self.error = error.localizedDescription }
                        }
                    } catch { self.error = error.localizedDescription }
                }
                .onChange(of: photo) { _, item in
                    guard let item else { return }; busy = true
                    Task {
                        defer { busy = false; photo = nil }
                        do { if let image = try await item.loadTransferable(type: ImportedPageImage.self) { insert(image.data, filename: image.filename) } }
                        catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
    private func insert(_ data: Data, filename: String) {
        let type: String = data.starts(with: [0x89,0x50,0x4e,0x47]) ? "image/png" : "image/jpeg"
        guard let result = performMutation({
            guard let (saved, media) = library.addImage(page: page, data: data, mediaType: type, filename: filename) else { return nil }
            var draft = saved
            draft.markdown += (draft.markdown.hasSuffix("\n\n") ? "" : "\n\n") + "![Bild](\(media.relativePath))\n"
            guard let revision = library.update(draft) else { return nil }
            draft.revision = revision; return library.currentPage(draft.id)
        }) else { error = library.saveError; return }
        page = result; updated(result); error = nil
    }
}

struct SpaceToolsSheet: View {
    let space: WritingSpace
    let library: WritingLibrary
    @State private var rules: String
    @State private var prompts: [ReusablePrompt]
    @Environment(\.dismiss) private var dismiss
    init(space: WritingSpace, library: WritingLibrary) { self.space = space; self.library = library; _rules = State(initialValue: space.assistantRules); _prompts = State(initialValue: space.reusablePrompts ?? []) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Schreibregeln für diesen Space") { TextEditor(text: $rules).frame(minHeight: 180) }
                Section("Prompts") {
                    ForEach($prompts) { $prompt in VStack { TextField("Titel", text: $prompt.title); TextField("Auftrag", text: $prompt.text, axis: .vertical) } }
                        .onDelete { prompts.remove(atOffsets: $0) }
                    Button("Prompt hinzufügen") { prompts.append(ReusablePrompt(title: "Neuer Prompt", text: "")) }
                }
                if let error = library.saveError { Text(error).foregroundStyle(.red) }
            }.navigationTitle(space.title).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { library.saveSpaceTools(spaceID: space.id, rules: rules, prompts: prompts); if library.saveError == nil { dismiss() } } }
            }
        }
    }
}

struct ImageBlockPicker: View {
    let page: WritingPage
    let library: WritingLibrary
    let afterBlockID: UUID?
    let updated: (WritingPage) -> Void
    var performMutation: PageToolMutation = { $0() }
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var busy = false
    @State private var description = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Bildbeschreibung") {
                    TextField("Alternativtext für das Bild", text: $description, axis: .vertical)
                    Text("Beschreiben Sie den Inhalt für Leserinnen und Leser, die das Bild nicht sehen können.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Bild auswählen") {
                    PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .compatible) { Label("Aus Fotos", systemImage: "photo.on.rectangle") }.disabled(busy)
                    Button("Aus Dateien", systemImage: "folder") { importing = true }.disabled(busy)
                    Text("PNG oder JPEG, bis zu 32 MB. Das Bild wird dauerhaft mit der Seite gespeichert und beim Export eingebettet.").font(.caption).foregroundStyle(.secondary)
                }
                if busy { ProgressView("Bildblock wird eingefügt …") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Bildblock einfügen")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg]) { result in
                    do {
                        let url = try result.get(); busy = true
                        Task {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() }; busy = false }
                            do {
                                let image = try await Task.detached(priority: .userInitiated) { try readBoundedImage(url) }.value
                                insert(image)
                            } catch { self.error = error.localizedDescription }
                        }
                    } catch { self.error = error.localizedDescription }
                }
                .onChange(of: photo) { _, item in
                    guard let item else { return }; busy = true
                    Task {
                        defer { busy = false; photo = nil }
                        do { if let image = try await item.loadTransferable(type: ImportedPageImage.self) { insert(image) } }
                        catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
    private func insert(_ image: ImportedPageImage) {
        guard let store = library.store else { error = "Die Bibliothek ist nicht verfügbar."; return }
        let type = image.data.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? "image/png" : "image/jpeg"
        guard let saved = performMutation({
            do {
                _ = try store.addImageBlock(pageID: page.id, data: image.data, mediaType: type, filename: image.filename, altText: description.trimmingCharacters(in: .whitespacesAndNewlines), afterBlockID: afterBlockID, baseRevision: page.revision)
                library.reload(); return library.currentPage(page.id)
            } catch { self.error = error.localizedDescription; return nil }
        }) else { if error == nil { error = library.saveError }; return }
        updated(saved); dismiss()
    }
}
