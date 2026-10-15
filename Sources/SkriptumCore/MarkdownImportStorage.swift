import Foundation
import Darwin

/// A transaction's new image blobs, addressed through pinned directories.
/// Deinitialization only closes descriptors: after an uncertain document commit
/// the caller must be able to retain blobs instead of deleting published data.
final class MarkdownImportStorage {
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
    }
    private struct Stamp: Equatable {
        let identity: Identity
        let mode: mode_t
        let owner: uid_t
        let links: nlink_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        init(_ info: stat) {
            identity = Identity(info); mode = info.st_mode; owner = info.st_uid
            links = info.st_nlink; size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanoseconds = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec; changedNanoseconds = info.st_ctimespec.tv_nsec
        }
    }
    private struct Created { let name: String; let stamp: Stamp }
    private let directory: URL
    private let root: Int32
    private let media: Int32
    private let rootIdentity: Identity
    private let mediaIdentity: Identity
    private var created: [Created] = []
    private var finished = false

    init(directory: URL) throws {
        let root = try Self.openDirectory(directory)
        var media = Darwin.openat(root, "media", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if media < 0, errno == ENOENT {
            if Darwin.mkdirat(root, "media", 0o700) != 0, errno != EEXIST {
                let failure = Self.failure(); Darwin.close(root); throw failure
            }
            media = Darwin.openat(root, "media", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard media >= 0 else { Darwin.close(root); throw LibraryError.invalidAttachment }
        do {
            let rootInfo = try Self.info(root), mediaInfo = try Self.info(media)
            guard Self.ownedDirectory(rootInfo), Self.ownedDirectory(mediaInfo) else { throw LibraryError.invalidAttachment }
            self.directory = directory; self.root = root; self.media = media
            rootIdentity = Identity(rootInfo); mediaIdentity = Identity(mediaInfo)
        } catch {
            Darwin.close(media); Darwin.close(root); throw error
        }
    }
    deinit { Darwin.close(media); Darwin.close(root) }

    func write(_ data: Data, attachment: MediaAttachment) throws {
        guard !finished, data.count == attachment.byteCount, data.count <= MediaValidation.maximumBytes,
              MediaValidation.digest(data) == attachment.sha256 else { throw LibraryError.invalidAttachment }
        try ICloudImagePayload.validateDescriptor(attachment)
        try checkDirectories()
        let temporary = ".markdown-import-" + UUID().uuidString
        let descriptor = Darwin.openat(media, temporary, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Self.failure() }
        let original: Identity
        do { original = Identity(try Self.info(descriptor)) }
        catch { Darwin.close(descriptor); throw error }
        defer {
            // A replaced temporary name is never removed by this transaction.
            removeOwnedName(temporary, identity: original)
            Darwin.close(descriptor)
        }
        let name = attachment.id.uuidString
        var installed = false, registered = false
        do {
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw Self.failure() }
                    offset += count
                }
            }
            guard Darwin.fsync(descriptor) == 0 else { throw Self.failure() }
            let written = try verifiedInfo(descriptor, data: data)
            guard Identity(written) == original, written.st_nlink == 1,
                  try namedInfo(temporary).map(Stamp.init) == Stamp(written) else { throw LibraryError.invalidAttachment }
            // linkat never overwrites an existing UUID name or symbolic link.
            guard Darwin.linkat(media, temporary, media, name, 0) == 0 else { throw Self.failure() }
            installed = true
            guard removeOwnedName(temporary, identity: original) else { throw LibraryError.invalidAttachment }
            let final = try verifiedInfo(descriptor, data: data)
            guard Identity(final) == original, final.st_nlink == 1,
                  try namedInfo(name).map(Stamp.init) == Stamp(final) else { throw LibraryError.invalidAttachment }
            created.append(Created(name: name, stamp: Stamp(final))); registered = true
            guard Darwin.fsync(media) == 0, Darwin.fsync(root) == 0 else { throw Self.failure() }
            try checkDirectories()
        } catch {
            // This write failed before returning to the publisher. Only remove
            // its own still-identical final file; otherwise retain an orphan.
            if installed && !registered, let current = try? verifiedInfo(descriptor, data: data),
               Identity(current) == original {
                removeUnchangedName(name, stamp: Stamp(current))
            }
            throw error
        }
    }

    func finishWrites() throws {
        guard !finished else { throw LibraryError.invalidAttachment }
        try checkDirectories()
        for file in created {
            guard try namedInfo(file.name).map(Stamp.init) == file.stamp else { throw LibraryError.invalidAttachment }
        }
        guard Darwin.fsync(media) == 0, Darwin.fsync(root) == 0 else { throw Self.failure() }
        try checkDirectories()
        finished = true
    }

    /// Best-effort rollback after the caller has proved that no new page was
    /// published. Replaced, modified or hard-linked names are deliberately kept.
    func rollback() {
        for file in created.reversed() { removeUnchangedName(file.name, stamp: file.stamp) }
        created.removeAll(); finished = true
        _ = Darwin.fsync(media); _ = Darwin.fsync(root)
    }

    private func checkDirectories() throws {
        guard Identity(try Self.info(root)) == rootIdentity, Identity(try Self.info(media)) == mediaIdentity else {
            throw LibraryError.invalidAttachment
        }
        var currentMedia = stat()
        guard Darwin.fstatat(root, "media", &currentMedia, AT_SYMLINK_NOFOLLOW) == 0,
              Self.ownedDirectory(currentMedia), Identity(currentMedia) == mediaIdentity else { throw LibraryError.invalidAttachment }
        // Commit uses the library URL. Refuse publication if that URL no longer
        // names this pinned root, even though writes to the old FD were safe.
        let currentRoot = try Self.openDirectory(directory)
        defer { Darwin.close(currentRoot) }
        guard Identity(try Self.info(currentRoot)) == rootIdentity else { throw LibraryError.invalidAttachment }
    }
    private func namedInfo(_ name: String) throws -> stat? {
        var value = stat()
        if Darwin.fstatat(media, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return value }
        if errno == ENOENT { return nil }
        throw Self.failure()
    }
    @discardableResult private func removeOwnedName(_ name: String, identity: Identity) -> Bool {
        guard let value = try? namedInfo(name), Identity(value) == identity,
              value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return false }
        return Darwin.unlinkat(media, name, 0) == 0
    }
    private func removeUnchangedName(_ name: String, stamp: Stamp) {
        guard let value = try? namedInfo(name), Stamp(value) == stamp,
              value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_uid == getuid(), value.st_nlink == 1 else { return }
        _ = Darwin.unlinkat(media, name, 0)
    }
    private func verifiedInfo(_ descriptor: Int32, data: Data) throws -> stat {
        let before = try Self.info(descriptor)
        guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), before.st_uid == getuid(),
              before.st_size == data.count else { throw LibraryError.invalidAttachment }
        var offset = 0, buffer = [UInt8](repeating: 0, count: 65_536)
        while offset < data.count {
            let count = Darwin.pread(descriptor, &buffer, min(buffer.count, data.count - offset), off_t(offset))
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw LibraryError.invalidAttachment }
            let start = data.index(data.startIndex, offsetBy: offset), end = data.index(start, offsetBy: count)
            guard buffer.prefix(count).elementsEqual(data[start..<end]) else {
                throw LibraryError.invalidAttachment
            }
            offset += count
        }
        let after = try Self.info(descriptor)
        guard Stamp(before) == Stamp(after) else { throw LibraryError.invalidAttachment }
        return after
    }
    private static func info(_ descriptor: Int32) throws -> stat {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else { throw failure() }
        return value
    }
    private static func ownedDirectory(_ value: stat) -> Bool {
        value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && value.st_uid == getuid()
    }
    private static func openDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0") else { throw LibraryError.invalidAttachment }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else { throw LibraryError.invalidAttachment }
        // /var and /tmp can be legitimate system aliases. Resolve only the
        // ancestors; the unchanged library leaf must itself pass O_NOFOLLOW.
        // Foundation may shorten /private/tmp back to the /tmp symlink even
        // after resolvingSymlinksInPath. realpath retains the physical parent.
        guard let resolvedParent = Darwin.realpath(url.deletingLastPathComponent().path, nil) else { throw failure() }
        defer { Darwin.free(resolvedParent) }
        let parent = String(cString: resolvedParent)
        let parts = (parent + (parent == "/" ? "" : "/") + name).split(separator: "/")
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { throw LibraryError.invalidAttachment }
        var descriptor = Darwin.open("/", O_SEARCH | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure() }
        for (index, part) in parts.enumerated() {
            let access = index == parts.count - 1 ? O_RDONLY | O_DIRECTORY : O_SEARCH
            let next = Darwin.openat(descriptor, String(part), access | O_NOFOLLOW | O_CLOEXEC)
            Darwin.close(descriptor)
            guard next >= 0 else { throw LibraryError.invalidAttachment }
            descriptor = next
        }
        do {
            guard ownedDirectory(try info(descriptor)) else { throw LibraryError.invalidAttachment }
            return descriptor
        } catch { Darwin.close(descriptor); throw error }
    }
    private static func failure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
