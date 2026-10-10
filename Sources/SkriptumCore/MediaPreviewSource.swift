import Foundation

/// An immutable, library-scoped preview lookup. Loading cannot select arbitrary
/// paths, fetch URLs or mutate the original attachment/export bytes.
public struct MediaPreviewSource: Sendable {
    public struct Request: Hashable, Sendable {
        let root: URL
        let attachment: MediaAttachment
        let refresh: UUID?
        public func hash(into hasher: inout Hasher) {
            hasher.combine(root); hasher.combine(refresh)
            hasher.combine(attachment.id); hasher.combine(attachment.filename)
            hasher.combine(attachment.mediaType); hasher.combine(attachment.byteCount); hasher.combine(attachment.sha256)
        }
        @concurrent public func data() async throws -> Data {
            try Task.checkCancellation()
            let data = try MediaValidation.readEncodedPreview(attachment, root: root)
            try Task.checkCancellation()
            return data
        }
    }
    private let root: URL
    private let attachments: [MediaAttachment]
    private let refresh: UUID?
    public init(root: URL, attachments: [MediaAttachment], refresh: UUID? = nil) {
        self.root = root; self.attachments = attachments; self.refresh = refresh
    }
    public func request(for path: String) -> Request? {
        guard let attachment = attachments.first(where: { $0.relativePath == path }) else { return nil }
        return Request(root: root, attachment: attachment, refresh: refresh)
    }
}
