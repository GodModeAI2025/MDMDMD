import Foundation
import Darwin

/// Only Foundation-provided app-container roots are resolved. No caller-supplied
/// library, import URL or interior directory can be normalized through this API.
enum WorkspaceSystemContainerRoots {
    static let documents = canonicalSystemDirectory(URL.documentsDirectory)
    static let applicationSupport = canonicalSystemDirectory(URL.applicationSupportDirectory)

    // The zero-argument properties above are the production entry points. This
    // helper also accepts isolated system-directory fixtures in regression tests.
    static func canonicalSystemDirectory(_ systemDirectory: URL) -> URL {
        guard systemDirectory.isFileURL else { return systemDirectory }
        var existing = systemDirectory
        var missing: [String] = []
        while true {
            let (path, failure) = existing.withUnsafeFileSystemRepresentation { source in
                guard let source else { return (nil as UnsafeMutablePointer<CChar>?, EINVAL) }
                let path = realpath(source, nil)
                return (path, errno)
            }
            if let path {
                defer { free(path) }
                // Foundation may preserve system aliases such as /var even in
                // resolvingSymlinksInPath(). The strict descriptor walkers need
                // the physical path, not an alias which O_NOFOLLOW must reject.
                var canonical = URL(fileURLWithFileSystemRepresentation: path, isDirectory: true, relativeTo: nil)
                for component in missing.reversed() {
                    canonical.appendPathComponent(component, isDirectory: true)
                }
                return canonical
            }
            // Application Support may not exist on first launch. Canonicalize
            // its existing system ancestor, without creating or replacing data.
            // Other IO failures remain subject to the normal fail-closed checks.
            guard failure == ENOENT, existing.pathComponents.count > 1 else { return systemDirectory }
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
    }
}
