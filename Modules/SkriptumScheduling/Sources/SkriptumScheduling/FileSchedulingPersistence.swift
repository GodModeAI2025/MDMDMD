import Darwin
import Foundation

public protocol SchedulingPersistence: Sendable {
  func read() throws -> Data?
  func write(_ value: Data) throws
}

/// Local atomic persistence only; no distributed locking or backend authority.
/// Every path component is opened relative to a pinned descriptor with no-follow.
public struct FileSchedulingPersistence: SchedulingPersistence {
  public let url: URL
  public init(url: URL) throws {
    guard url.isFileURL, url.baseURL == nil, url.query == nil, url.fragment == nil,
      url.host == nil || url.host == "" || url.host == "localhost",
      !url.pathComponents.contains(".."), !url.path.contains("\0"),
      !url.lastPathComponent.isEmpty, url.lastPathComponent != "/"
    else { throw SchedulingError.unsafeFile }
    self.url = url
  }
  private func ioError() -> Error {
    if errno == ELOOP || errno == ENOTDIR { return SchedulingError.unsafeFile }
    return NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
  }
  private func parent(create: Bool) throws -> Int32? {
    var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw ioError() }
    do {
      for component in url.deletingLastPathComponent().pathComponents.dropFirst() {
        var next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if next < 0 && errno == ENOENT && create {
          guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else {
            throw ioError()
          }
          next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        if next < 0 {
          if errno == ENOENT && !create {
            close(descriptor)
            return nil
          }
          throw ioError()
        }
        close(descriptor)
        descriptor = next
      }
      return descriptor
    } catch {
      close(descriptor)
      throw error
    }
  }
  public func read() throws -> Data? {
    guard let directory = try parent(create: false) else { return nil }
    defer { close(directory) }
    let descriptor = openat(
      directory, url.lastPathComponent, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    if descriptor < 0 {
      if errno == ENOENT { return nil }
      throw ioError()
    }
    defer { close(descriptor) }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0 else { throw ioError() }
    guard attributes.st_mode & S_IFMT == S_IFREG else { throw SchedulingError.unsafeFile }
    guard attributes.st_size <= SchedulingState.maximumFileBytes else {
      throw SchedulingError.persistenceTooLarge
    }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count < 0 {
        if errno == EINTR { continue }
        throw ioError()
      }
      if count == 0 { return result }
      guard count <= SchedulingState.maximumFileBytes - result.count else {
        throw SchedulingError.persistenceTooLarge
      }
      result.append(contentsOf: buffer.prefix(count))
    }
  }
  public func write(_ value: Data) throws {
    guard value.count <= SchedulingState.maximumFileBytes else {
      throw SchedulingError.persistenceTooLarge
    }
    guard let directory = try parent(create: true) else { throw SchedulingError.unsafeFile }
    defer { close(directory) }
    var attributes = stat()
    let status = fstatat(directory, url.lastPathComponent, &attributes, AT_SYMLINK_NOFOLLOW)
    if status == 0 {
      guard attributes.st_mode & S_IFMT == S_IFREG else { throw SchedulingError.unsafeFile }
    } else if errno != ENOENT {
      throw ioError()
    }
    let temporary = ".scheduler-" + UUID().uuidString + ".tmp"
    let descriptor = openat(
      directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw ioError() }
    defer {
      close(descriptor)
      unlinkat(directory, temporary, 0)
    }
    try value.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if count < 0 {
          if errno == EINTR { continue }
          throw ioError()
        }
        guard count > 0 else { throw SchedulingError.unsafeFile }
        offset += count
      }
    }
    guard fsync(descriptor) == 0 else { throw ioError() }
    guard renameat(directory, temporary, directory, url.lastPathComponent) == 0 else {
      throw ioError()
    }
  }
}
