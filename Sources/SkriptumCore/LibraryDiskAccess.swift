import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Cooperative cross-process exclusion. The lock inode is never replaced or
/// removed during normal use; kernel ownership ends when its descriptor closes.
@MainActor enum LibraryDiskAccess {
    struct Version: Equatable {
        let device: Int64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
        func hasSamePayloadCoordinates(as other: Version) -> Bool {
            device == other.device && inode == other.inode && size == other.size &&
            modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
        }
    }
    nonisolated static func withExclusiveLock<T>(directory: URL, body: () throws -> T) throws -> T {
        let path = directory.appendingPathComponent(".library.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw failure() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw failure() }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LibraryError.invalidLibrary }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw LibraryError.revisionConflict }
            throw failure()
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
    nonisolated static func version(of file: URL) throws -> Version? {
        let descriptor = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw failure()
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw failure() }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LibraryError.invalidLibrary }
        return version(for: info)
    }
    /// Metadata-only changes may be admitted only after hashing the same regular
    /// file descriptor. A replaced path, changed payload or concurrent stat
    /// change fails closed. Callers hold the cooperative library lock.
    nonisolated static func contentDigest(of file: URL, matching expected: Version) throws -> SHA256.Digest? {
        guard (0...64 * 1024 * 1024).contains(expected.size) else { return nil }
        let descriptor = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw failure() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw failure() }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), version(for: info) == expected else { return nil }
        var hash = SHA256(), count: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw failure()
            }
            if readCount == 0 { break }
            count += Int64(readCount)
            guard count <= expected.size else { return nil }
            hash.update(data: Data(buffer.prefix(readCount)))
        }
        guard fstat(descriptor, &info) == 0 else { throw failure() }
        guard count == expected.size, version(for: info) == expected,
              try version(of: file) == expected else { return nil }
        return hash.finalize()
    }
    nonisolated private static func version(for info: stat) -> Version {
        #if canImport(Darwin)
        let modified = info.st_mtimespec, changed = info.st_ctimespec
        #else
        let modified = info.st_mtim, changed = info.st_ctim
        #endif
        return Version(device: Int64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
            modifiedSeconds: Int64(modified.tv_sec), modifiedNanoseconds: Int64(modified.tv_nsec),
            changedSeconds: Int64(changed.tv_sec), changedNanoseconds: Int64(changed.tv_nsec))
    }
    nonisolated private static func failure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
