import Foundation
import SkriptumWritingQuality

enum GraalGrammarError: Error {
    case creation(Int32), heap(Int32), resources(Int32), response(Int32), teardown(Int32)
}

/// Research integration driver. The caller verifies every resource byte before
/// constructing this driver. Not included in production app targets yet.
struct GraalBundledGrammarEngine: BundledGrammarEngine {
    let resourceRoot: URL
    let languages: Set<String>

    func check(text: String, language: String) throws -> Data {
        guard !Thread.isMainThread else { throw QualityError.invalidConfiguration }
        guard languages.contains(language), !language.isEmpty, language.utf8.count <= 32 else { throw QualityError.unsupportedLanguage }
        guard text.utf8.count <= 100_000, !text.contains("\0"),
              resourceRoot.isFileURL, resourceRoot.path.utf8.count <= 4096 else { throw QualityError.inputTooLarge }
        var nativeThread: OpaquePointer?
        let created = graal_create_isolate(nil, nil, &nativeThread)
        guard created == 0, let thread = nativeThread else { throw GraalGrammarError.creation(created) }
        // Every operation, including teardown, stays on this synchronous thread.
        let result: Result<Data, Error> = Result {
            let heap = scriptum_quality_set_heap_limit(thread, 256 * 1024 * 1024)
            guard heap == 0 else { throw GraalGrammarError.heap(heap) }
            let root = resourceRoot.path
            let configured = root.withCString {
                scriptum_quality_set_resource_root(thread, UnsafeMutablePointer(mutating: $0), Int32(root.utf8.count))
            }
            guard configured == 0 else { throw GraalGrammarError.resources(configured) }
            var output = [CChar](repeating: 0, count: 2_000_000)
            let length = language.withCString { code in
                text.withCString { input in
                    output.withUnsafeMutableBufferPointer { buffer in
                        scriptum_quality_check(thread, UnsafeMutablePointer(mutating: code), Int32(language.utf8.count),
                            UnsafeMutablePointer(mutating: input), Int32(text.utf8.count), buffer.baseAddress, Int32(buffer.count))
                    }
                }
            }
            guard length > 0, length <= output.count else { throw GraalGrammarError.response(length) }
            return Data(output.prefix(Int(length)).map { UInt8(bitPattern: $0) })
        }
        let teardown = graal_tear_down_isolate(thread)
        guard teardown == 0 else { throw GraalGrammarError.teardown(teardown) }
        return try result.get()
    }
}
