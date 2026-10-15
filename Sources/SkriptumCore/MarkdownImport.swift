import Foundation
import Darwin
import Markdown

public enum MarkdownImportError: Error, LocalizedError, Equatable {
    case invalidUTF8, sourceTooLarge, unsafeSource, missingImage(String), unsupportedImage(String), conflictingImagePath(String), folderRequired
    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: "Die Markdown-Datei ist kein gültiger UTF-8-Text."
        case .sourceTooLarge: "Der Import ist zu groß (höchstens 16 MB Text, 32 MB je Bild und 512 MB insgesamt)."
        case .unsafeSource: "Die Quelle liegt außerhalb des gewählten Ordners oder enthält eine symbolische Verknüpfung."
        case .missingImage(let path): "Das Bild „\(path)“ fehlt im gewählten Ordner. Es wurde nichts importiert."
        case .unsupportedImage(let path): "Das Bild „\(path)“ kann nicht übernommen werden. Unterstützt werden lokale PNG- und JPEG-Bilder ohne übergeordnete Pfade (..), URL-Parameter oder Fragmente."
        case .conflictingImagePath(let path): "Der Bildpfad „\(path)“ kollidiert mit einem anderen Bild oder einer reservierten Exportdatei (document.md, manifest.json, README.md). Bitte benennen Sie ihn vor dem Import um."
        case .folderRequired: "Dieser Text enthält Bilder. Wählen Sie „Markdown mit Bildern importieren“ und den Ordner mit Text und Bildern."
        }
    }
}

/// Fully read and validated before any library record is published. No caller
/// can create a partially validated import or substitute its attachment bytes.
public struct MarkdownImport: Sendable {
    public let title: String
    public let markdown: String
    public let attachments: [MediaAttachment]
    fileprivate let images: [Data]
    public let byteCount: Int
    public static let maximumBytes = 512 * 1024 * 1024
    private init(title: String, markdown: String, attachments: [MediaAttachment], images: [Data], byteCount: Int) {
        self.title = title; self.markdown = markdown; self.attachments = attachments; self.images = images; self.byteCount = byteCount
    }

    /// The caller owns security-scoped access to the chosen file or folder.
    /// A file-only selection never grants access to its neighbouring images.
    public static func read(file: URL, sourceDirectory: URL? = nil) throws -> Self {
        guard file.isFileURL else { throw MarkdownImportError.unsafeSource }
        if let sourceDirectory {
            let path = try relativePath(of: file, in: sourceDirectory)
            return try coordinated(sourceDirectory) { coordinatedRoot in
                let reader = try ImportDirectory(coordinatedRoot)
                return try prepare(bytes: reader.read(path, maximum: 16 * 1024 * 1024), path: path, reader: reader)
            }
        }
        return try coordinated(file) { coordinatedFile in
            // A file-scoped grant need not allow opening its parent directory.
            // Open only the exact coordinated file, never its neighbours.
            return try prepare(bytes: ImportDirectory.readSelectedFile(coordinatedFile, maximum: 16 * 1024 * 1024),
                               path: file.lastPathComponent, reader: nil)
        }
    }

    /// A bounded catalog of names, not an implicit import of every text. The UI
    /// asks which documents to import; symlinked files/directories are omitted.
    public static func catalog(in directory: URL) throws -> [String] {
        return try coordinated(directory) { coordinatedRoot in
            let reader = try ImportDirectory(coordinatedRoot)
            var result: [String] = [], pending = [""], visited = 0
            while let parent = pending.popLast() {
                for entry in try reader.entries(at: parent) {
                    visited += 1
                    guard visited <= 10_000 else { throw MarkdownImportError.sourceTooLarge }
                    if entry.name.hasPrefix(".") { continue }
                    let path = parent.isEmpty ? entry.name : parent + "/" + entry.name
                    if entry.directory {
                        guard path.split(separator: "/").count < 32 else { continue }
                        pending.append(path)
                    } else if ["md", "markdown", "txt"].contains((entry.name as NSString).pathExtension.lowercased()) {
                        result.append(path)
                        guard result.count <= 1000 else { throw MarkdownImportError.sourceTooLarge }
                    }
                }
            }
            return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    private static func prepare(bytes: Data, path: String, reader: ImportDirectory?) throws -> Self {
        guard let markdown = String(validating: bytes, as: UTF8.self), Data(markdown.utf8) == bytes else { throw MarkdownImportError.invalidUTF8 }
        let document = Document(parsing: markdown)
        var stack: [any Markup] = [document], visited = 0, total = bytes.count
        var attachments: [MediaAttachment] = [], images: [Data] = [], seen = Set<Data>()
        var archiveNames: [String: (path: Data, bytes: Data)] = [:]
        let parent = (path as NSString).deletingLastPathComponent
        while let node = stack.popLast() {
            visited += 1
            guard visited <= 200_000 else { throw MarkdownImportError.sourceTooLarge }
            if let image = node as? Markdown.Image {
                guard let reader else { throw MarkdownImportError.folderRequired }
                let destination = image.source ?? ""
                guard let imagePath = MarkdownAssetPath.filePath(for: destination) else { throw MarkdownImportError.unsupportedImage(destination) }
                guard !["document.md", "manifest.json", "readme.md"].contains(imagePath.split(separator: "/").first?.lowercased() ?? "") else {
                    throw MarkdownImportError.conflictingImagePath(destination)
                }
                if seen.insert(Data(destination.utf8)).inserted {
                    let resolved = parent.isEmpty ? imagePath : parent + "/" + imagePath
                    let data: Data
                    do { data = try reader.read(resolved, maximum: MediaValidation.maximumBytes) }
                    catch MarkdownImportError.unsafeSource { throw MarkdownImportError.unsafeSource }
                    catch MarkdownImportError.sourceTooLarge { throw MarkdownImportError.sourceTooLarge }
                    catch { throw MarkdownImportError.missingImage(destination) }
                    guard data.count <= maximumBytes - total else { throw MarkdownImportError.sourceTooLarge }
                    total += data.count
                    let name = imagePath.lowercased()
                    if let previous = archiveNames[name], previous.path != Data(imagePath.utf8) || previous.bytes != data {
                        throw MarkdownImportError.conflictingImagePath(destination)
                    }
                    archiveNames[name] = (Data(imagePath.utf8), data)
                    let mediaType: String
                    if (try? MediaValidation.validate(data, mediaType: "image/png")) != nil { mediaType = "image/png" }
                    else if (try? MediaValidation.validate(data, mediaType: "image/jpeg")) != nil { mediaType = "image/jpeg" }
                    else { throw MarkdownImportError.unsupportedImage(destination) }
                    let attachment = MediaAttachment(filename: (imagePath as NSString).lastPathComponent, mediaType: mediaType,
                        byteCount: data.count, sha256: MediaValidation.digest(data), sourcePath: destination)
                    attachments.append(attachment); images.append(data)
                }
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return Self(title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                    markdown: markdown, attachments: attachments, images: images, byteCount: total)
    }
    private static func relativePath(of file: URL, in directory: URL) throws -> String {
        guard directory.isFileURL else { throw MarkdownImportError.unsafeSource }
        let root = directory.standardizedFileURL.pathComponents, parts = file.standardizedFileURL.pathComponents
        guard parts.count > root.count, zip(parts, root).allSatisfy({ $0.utf8.elementsEqual($1.utf8) }) else { throw MarkdownImportError.unsafeSource }
        return parts.dropFirst(root.count).joined(separator: "/")
    }
    private static func coordinated<T>(_ url: URL, read: (URL) throws -> T) throws -> T {
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw MarkdownImportError.unsafeSource }
        var coordinationError: NSError?, result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try read(coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw MarkdownImportError.unsafeSource }
        return try result.get()
    }
}

/// Resolve every component relative to an already-open selected directory.
/// O_NOFOLLOW prevents even a replaced intermediate symlink from escaping it.
private final class ImportDirectory {
    let descriptor: Int32
    init(_ root: URL) throws {
        guard root.isFileURL else { throw MarkdownImportError.unsafeSource }
        descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MarkdownImportError.unsafeSource }
    }
    deinit { Darwin.close(descriptor) }
    private func open(_ path: String, directory: Bool = false) throws -> Int32 {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else { throw MarkdownImportError.unsafeSource }
        var current = Darwin.dup(descriptor)
        guard current >= 0 else { throw MarkdownImportError.unsafeSource }
        for (index, part) in parts.enumerated() {
            let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | ((index < parts.count - 1 || directory) ? O_DIRECTORY : 0)
            let next = Darwin.openat(current, String(part), flags)
            Darwin.close(current)
            guard next >= 0 else {
                if errno == ELOOP || errno == ENOTDIR { throw MarkdownImportError.unsafeSource }
                throw CocoaError(.fileReadNoSuchFile)
            }
            current = next
        }
        return current
    }
    func read(_ path: String, maximum: Int) throws -> Data {
        let fd = try open(path); defer { Darwin.close(fd) }
        return try Self.readDescriptor(fd, maximum: maximum)
    }
    static func readSelectedFile(_ url: URL, maximum: Int) throws -> Data {
        guard url.isFileURL else { throw MarkdownImportError.unsafeSource }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw MarkdownImportError.unsafeSource }
        defer { Darwin.close(fd) }
        return try readDescriptor(fd, maximum: maximum)
    }
    private static func readDescriptor(_ fd: Int32, maximum: Int) throws -> Data {
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw MarkdownImportError.unsafeSource }
        guard info.st_size >= 0, info.st_size <= maximum else { throw MarkdownImportError.sourceTooLarge }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw CocoaError(.fileReadUnknown) }
            guard count <= maximum - data.count else { throw MarkdownImportError.sourceTooLarge }
            if count == 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard Darwin.fstat(fd, &after) == 0, info.st_size == after.st_size, info.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              info.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec, data.count == info.st_size else { throw CocoaError(.fileReadUnknown) }
        return data
    }
    func entries(at path: String) throws -> [(name: String, directory: Bool)] {
        let fd = path.isEmpty ? Darwin.dup(descriptor) : try open(path, directory: true)
        guard fd >= 0, let stream = Darwin.fdopendir(fd) else { if fd >= 0 { Darwin.close(fd) }; throw MarkdownImportError.unsafeSource }
        defer { Darwin.closedir(stream) }
        var result: [(String, Bool)] = []
        while let entry = Darwin.readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var info = stat()
            guard Darwin.fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw MarkdownImportError.unsafeSource }
            let kind = info.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFDIR) || kind == mode_t(S_IFREG) { result.append((name, kind == mode_t(S_IFDIR))) }
            guard result.count <= 10_000 else { throw MarkdownImportError.sourceTooLarge }
        }
        return result
    }
}

extension LibraryStore {
    /// Publish all selected pages only after their immutable images are present.
    /// On failure, delete only blobs created by this transaction; no partial page
    /// or durable-change notification escapes. A crash can leave unused blobs,
    /// never a published page whose images have not been written.
    @discardableResult public func importMarkdown(_ documents: [MarkdownImport], spaceID: UUID) throws -> [Page] {
        try requireWritable()
        guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw LibraryError.missingSpace }
        guard !documents.isEmpty, documents.count <= 1000 else { throw MarkdownImportError.sourceTooLarge }
        var total = 0
        for document in documents {
            guard document.byteCount <= MarkdownImport.maximumBytes - total else { throw MarkdownImportError.sourceTooLarge }
            total += document.byteCount
        }
        let pages = documents.map { document in
            var page = Page(spaceID: spaceID, title: document.title, markdown: document.markdown)
            page.attachments = document.attachments.isEmpty ? nil : document.attachments
            return page
        }
        var candidate = snapshot; candidate.pages.append(contentsOf: pages)
        try Self.validate(candidate)
        let storage = try MarkdownImportStorage(directory: directory)
        var publishing = false
        do {
            for document in documents {
                for (attachment, bytes) in zip(document.attachments, document.images) {
                    try storage.write(bytes, attachment: attachment)
                }
            }
            try storage.finishWrites()
            publishing = true
            try commit(candidate)
            return pages
        } catch {
            // commit can fail after its atomic library.json write (for example
            // while reading filesystem metadata). Only positive durable proof
            // that these fresh IDs were NOT published permits blob rollback.
            let ids = Set(documents.flatMap(\.attachments).map(\.id))
            if !publishing || markdownImportWasNotPublished(ids) { storage.rollback() }
            throw error
        }
    }
    private func markdownImportWasNotPublished(_ imageIDs: Set<UUID>) -> Bool {
        (try? LibraryDiskAccess.withExclusiveLock(directory: directory) {
            let reader = try ImportDirectory(directory)
            let durable = try JSONDecoder().decode(LibrarySnapshot.self, from: reader.read("library.json", maximum: 64 * 1024 * 1024))
            guard (1...2).contains(durable.schemaVersion) else { return false }
            try Self.validate(durable)
            return Self.markdownImportIsUnreferenced(imageIDs, in: durable)
        }) == true
    }
    static func markdownImportIsUnreferenced(_ imageIDs: Set<UUID>, in durable: LibrarySnapshot) -> Bool {
        !(durable.pages + durable.revisions.map(\.page)).contains { page in
            (page.attachments ?? []).contains { imageIDs.contains($0.id) }
        }
    }
}
