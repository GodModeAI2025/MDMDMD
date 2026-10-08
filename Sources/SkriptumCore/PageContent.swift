import Foundation
import CryptoKit
import ImageIO

public enum MediaValidation {
    public static let maximumBytes = 32 * 1024 * 1024
    public static func validate(_ data: Data, mediaType: String) throws {
        guard !data.isEmpty, data.count <= maximumBytes,
              ["image/png", "image/jpeg"].contains(mediaType),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              type == (mediaType == "image/png" ? "public.png" : "public.jpeg"),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384,
              width * height <= 40_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw LibraryError.invalidAttachment }
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func read(_ attachment: MediaAttachment, root: URL) throws -> Data {
        let media = root.appendingPathComponent("media")
        let url = root.appendingPathComponent(attachment.relativePath)
        for path in [media, url] {
            guard try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.invalidAttachment }
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue == attachment.byteCount, size.intValue <= maximumBytes else { throw LibraryError.invalidAttachment }
        let data = try Data(contentsOf: url)
        guard digest(data) == attachment.sha256 else { throw LibraryError.invalidAttachment }
        try validate(data, mediaType: attachment.mediaType)
        return data
    }
}

extension LibraryStore {
    public func setRules(pageID: UUID, rules: String, baseRevision: UUID) throws {
        try edit(pageID) { guard $0.revision == baseRevision else { throw LibraryError.revisionConflict }; $0.assistantRules = rules }
    }
    public func setRules(spaceID: UUID, rules: String) throws {
        var state = snapshot
        guard let index = state.spaces.firstIndex(where: { $0.id == spaceID }) else { throw LibraryError.missingSpace }
        state.spaces[index].assistantRules = rules; try commit(state)
    }
    public func setPrompts(pageID: UUID, prompts: [ReusablePrompt], baseRevision: UUID) throws {
        guard Set(prompts.map(\.id)).count == prompts.count else { throw LibraryError.invalidLibrary }
        try edit(pageID) { guard $0.revision == baseRevision else { throw LibraryError.revisionConflict }; $0.reusablePrompts = prompts }
    }
    public func setPrompts(spaceID: UUID, prompts: [ReusablePrompt]) throws {
        guard Set(prompts.map(\.id)).count == prompts.count else { throw LibraryError.invalidLibrary }
        var state = snapshot
        guard let index = state.spaces.firstIndex(where: { $0.id == spaceID }) else { throw LibraryError.missingSpace }
        state.spaces[index].reusablePrompts = prompts; try commit(state)
    }
    public func setWordGoal(pageID: UUID, goal: Int?, baseRevision: UUID) throws {
        guard goal.map({ $0 >= 0 }) ?? true else { throw LibraryError.invalidWordGoal }
        try edit(pageID) { guard $0.revision == baseRevision else { throw LibraryError.revisionConflict }; $0.wordGoal = goal }
    }
    @discardableResult public func addAttachment(pageID: UUID, data: Data, mediaType: String, filename: String, baseRevision: UUID) throws -> MediaAttachment {
        try MediaValidation.validate(data, mediaType: mediaType)
        guard !filename.isEmpty, !filename.contains("/"), !filename.contains("\\"), filename != ".", filename != ".." else { throw LibraryError.invalidAttachment }
        let attachment = MediaAttachment(filename: filename, mediaType: mediaType, byteCount: data.count, sha256: MediaValidation.digest(data))
        let folder = directory.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.invalidAttachment }
        let file = directory.appendingPathComponent(attachment.relativePath)
        try data.write(to: file, options: [.withoutOverwriting])
        do { try edit(pageID) { guard $0.revision == baseRevision else { throw LibraryError.revisionConflict }; $0.attachments = ($0.attachments ?? []) + [attachment] } }
        catch { try? FileManager.default.removeItem(at: file); throw error }
        return attachment
    }
    public func attachmentData(_ attachment: MediaAttachment) throws -> Data { try MediaValidation.read(attachment, root: directory) }
    public func removeAttachment(pageID: UUID, attachmentID: UUID, baseRevision: UUID) throws {
        // Keep immutable bytes: historical revisions may still reference this media.
        try edit(pageID) {
            guard $0.revision == baseRevision else { throw LibraryError.revisionConflict }
            guard ($0.attachments ?? []).contains(where: { $0.id == attachmentID }) else { throw LibraryError.missingAttachment }
            $0.attachments?.removeAll { $0.id == attachmentID }
        }
    }
}

public struct ScriptumPackageManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let library: LibrarySnapshot
    public init(library: LibrarySnapshot) { formatVersion = 1; self.library = library }
}

extension LibraryStore {
    private static func allAttachments(_ state: LibrarySnapshot) throws -> [MediaAttachment] {
        var attachments: [UUID: MediaAttachment] = [:]
        for attachment in (state.pages + state.revisions.map(\.page)).flatMap({ $0.attachments ?? [] }) {
            if let prior = attachments[attachment.id], prior != attachment { throw LibraryError.invalidAttachment }
            attachments[attachment.id] = attachment
        }
        return attachments.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public func exportPackage(to destination: URL) throws {
        guard !hasActiveEdits else { throw LibraryError.editInProgress }
        try Self.writePackage(snapshot, mediaRoot: directory, destination: destination)
    }
    private static func writePackage(_ state: LibrarySnapshot, mediaRoot: URL, destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw LibraryError.destinationExists }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".scriptum-" + UUID().uuidString)
        try fm.createDirectory(at: staging.appendingPathComponent("media"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let manifest = try encoder.encode(ScriptumPackageManifest(library: state))
        guard manifest.count <= 64 * 1024 * 1024 else { throw LibraryError.invalidPackage }
        var total = manifest.count
        try manifest.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        for attachment in try allAttachments(state) {
            let data = try MediaValidation.read(attachment, root: mediaRoot)
            total += data.count
            guard total <= 512 * 1024 * 1024 else { throw LibraryError.invalidPackage }
            try data.write(to: staging.appendingPathComponent(attachment.relativePath), options: .atomic)
        }
        try fm.moveItem(at: staging, to: destination)
    }
    /// Imports a complete library into a new directory. Existing libraries are never merged or overwritten.
    public static func importPackage(from source: URL, to destination: URL) throws -> LibraryStore {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw LibraryError.destinationExists }
        guard source.pathExtension == "scriptum", try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.invalidPackage }
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = source.appendingPathComponent("manifest.json")
        guard try manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let size = try fm.attributesOfItem(atPath: manifestURL.path)[.size] as? NSNumber,
              size.intValue <= 64 * 1024 * 1024 else { throw LibraryError.invalidPackage }
        let manifest = try JSONDecoder().decode(ScriptumPackageManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.formatVersion == 1, manifest.library.schemaVersion == 1 else { throw LibraryError.unsupportedSchema }
        try validate(manifest.library)
        let attachments = try allAttachments(manifest.library)
        let expected = Set(["manifest.json", "media"] + attachments.map(\.relativePath))
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]) else { throw LibraryError.invalidPackage }
        var total = size.intValue
        for case let url as URL in enumerator {
            let relative = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            guard expected.contains(relative), values.isSymbolicLink != true,
                  (relative == "media" ? values.isDirectory == true : values.isRegularFile == true) else { throw LibraryError.invalidPackage }
            if relative != "manifest.json", values.isRegularFile == true {
                total += (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? Int.max / 2
                guard total <= 512 * 1024 * 1024 else { throw LibraryError.invalidPackage }
            }
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".scriptum-import-" + UUID().uuidString)
        try fm.createDirectory(at: staging.appendingPathComponent("media"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for attachment in attachments { try MediaValidation.read(attachment, root: source).write(to: staging.appendingPathComponent(attachment.relativePath), options: .atomic) }
        try JSONEncoder().encode(manifest.library).write(to: staging.appendingPathComponent("library.json"), options: .atomic)
        _ = try LibraryStore(directory: staging)
        try fm.moveItem(at: staging, to: destination)
        return try LibraryStore(directory: destination)
    }
}

extension LibraryStore {
    /// Recovery owns independent, verified immutable blobs before its record is published.
    public func archiveAttachments(_ attachments: [MediaAttachment], to recoveryRoot: URL) throws {
        let payloads = try attachments.map { ($0, try attachmentData($0)) }
        let media = recoveryRoot.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        guard try media.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.invalidAttachment }
        for (attachment, data) in payloads {
            let destination = recoveryRoot.appendingPathComponent(attachment.relativePath)
            if FileManager.default.fileExists(atPath: destination.path) || (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil {
                _ = try MediaValidation.read(attachment, root: recoveryRoot)
            } else {
                try data.write(to: destination, options: .withoutOverwriting)
                _ = try MediaValidation.read(attachment, root: recoveryRoot)
            }
        }
    }
    /// Creates all recovered metadata in one library commit. Attachment IDs and
    /// source paths remain unchanged; missing or corrupt media aborts creation.
    @discardableResult public func createRecoveredPage(from draft: Page, spaceID: UUID, parentID: UUID? = nil, mediaRoot: URL, fallbackMediaRoot: URL? = nil) throws -> Page {
        guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw LibraryError.missingSpace }
        if let parentID, let parent = snapshot.pages.first(where: { $0.id == parentID }), parent.trashedAt != nil { throw LibraryError.trashedParent }
        var recovered = draft
        recovered.id = UUID(); recovered.revision = UUID(); recovered.spaceID = spaceID; recovered.parentID = parentID
        recovered.createdAt = Date(); recovered.modifiedAt = recovered.createdAt; recovered.trashedAt = nil
        var candidate = snapshot; candidate.pages.append(recovered)
        try Self.validate(candidate)
        _ = try Self.allAttachments(candidate)
        let payloads = try (recovered.attachments ?? []).map { attachment -> (MediaAttachment, Data) in
            let archived = mediaRoot.appendingPathComponent(attachment.relativePath)
            if FileManager.default.fileExists(atPath: archived.path) { return (attachment, try MediaValidation.read(attachment, root: mediaRoot)) }
            guard let fallbackMediaRoot else { throw LibraryError.missingAttachment }
            return (attachment, try MediaValidation.read(attachment, root: fallbackMediaRoot))
        }
        var createdFiles: [URL] = []
        do {
            if !payloads.isEmpty {
                let media = directory.appendingPathComponent("media")
                try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
                guard try media.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.invalidAttachment }
            }
            for (attachment, data) in payloads {
                let destination = directory.appendingPathComponent(attachment.relativePath)
                if FileManager.default.fileExists(atPath: destination.path) || (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil { _ = try MediaValidation.read(attachment, root: directory) }
                else { createdFiles.append(destination); try data.write(to: destination, options: .withoutOverwriting) }
            }
            try commit(candidate)
            return recovered
        } catch {
            for url in createdFiles { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
