import Foundation
import CryptoKit
#if canImport(ScriptumGrammar)
import ScriptumGrammar
#endif

public enum BundledGrammarError: Error, Sendable, Equatable, LocalizedError {
    case notInstalled, invalidResources, nativeFailure(Int32)
    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Die lokale Grammatikprüfung ist in diesem Build nicht installiert."
        case .invalidResources: "Die Dateien der lokalen Grammatikprüfung fehlen oder sind beschädigt. Bitte die App erneut installieren."
        case .nativeFailure: "Die lokale Grammatikprüfung konnte nicht abgeschlossen werden. Es wurden keine Teilergebnisse übernommen."
        }
    }
}

/// Availability is a build capability, never a promise inferred from Apple's
/// spelling dictionaries. The native framework remains an explicit build input.
public enum BundledGrammarRuntime {
    public static var isLinked: Bool {
        #if canImport(ScriptumGrammar)
        true
        #else
        false
        #endif
    }

    /// Exact codes exercised through the pinned native engine and source-safe
    /// reviewer. This catalog does not assert equal quality in every language.
    public static let languageCodes = [
        "ar", "ast-ES", "be-BY", "br-FR", "ca-ES", "da-DK", "de", "el-GR", "en", "eo",
        "es", "fa", "fr", "ga-IE", "gl-ES", "it", "ja-JP", "km-KH", "nl", "pl-PL",
        "pt", "ro-RO", "ru-RU", "sk-SK", "sl-SI", "sv", "ta-IN", "tl-PH", "zh-CN"
    ]

    /// Validate in a concurrent task before handing the synchronous driver to
    /// the process-wide native worker. No network, extraction or writable cache.
    @concurrent public static func load(resourceBundleURL: URL?) async throws -> any BundledGrammarEngine {
        try Task.checkCancellation()
        #if canImport(ScriptumGrammar)
        guard let resourceBundleURL else { throw BundledGrammarError.invalidResources }
        do {
            let root = try GrammarResourceVerifier.verify(root: resourceBundleURL, pin: .languageTool66)
            return InstalledGrammarEngine(resourceRoot: root)
        } catch is CancellationError { throw CancellationError() }
        catch { throw BundledGrammarError.invalidResources }
        #else
        throw BundledGrammarError.notInstalled
        #endif
    }
}

struct GrammarResourcePin: Sendable {
    let manifestSHA256: String
    let files: Int
    let bytes: Int
    static let languageTool66 = Self(
        manifestSHA256: "2ddd9b3c07bee931ae6474bbded3774a1475c9fff8ff2178d8541a1cf32be526",
        files: 1888, bytes: 337_383_291)
}

enum GrammarResourceVerifier {
    private struct Manifest: Decodable {
        let engine: String, version: String, resources: [Resource]
    }
    private struct Resource: Decodable { let path: String, bytes: Int, sha256: String }

    static func verify(root: URL, pin: GrammarResourcePin) throws -> URL {
        try Task.checkCancellation()
        guard root.isFileURL, root.path.utf8.count <= 4096,
              try isDirectory(root), !isLink(root) else { throw BundledGrammarError.invalidResources }
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard !isLink(manifestURL), try regularSize(manifestURL) <= 4 * 1024 * 1024 else {
            throw BundledGrammarError.invalidResources
        }
        let data = try Data(contentsOf: manifestURL)
        guard digest(data) == pin.manifestSHA256 else { throw BundledGrammarError.invalidResources }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.engine == "LanguageTool", manifest.version == "6.6",
              manifest.resources.count == pin.files, pin.files > 0, pin.files <= 5000 else {
            throw BundledGrammarError.invalidResources
        }
        var names = Set<String>(), total = 0
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        for record in manifest.resources {
            try Task.checkCancellation()
            let parts = record.path.split(separator: "/", omittingEmptySubsequences: false)
            guard record.path.hasPrefix("org/languagetool/"), !record.path.contains("\\"),
                  !record.path.contains("\0"), record.path.utf8.count <= 4096,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  names.insert(record.path.precomposedStringWithCanonicalMapping.lowercased()).inserted,
                  record.bytes >= 0, record.bytes <= pin.bytes - total else {
                throw BundledGrammarError.invalidResources
            }
            var target = canonicalRoot
            for part in parts {
                target.appendPathComponent(String(part))
                guard !isLink(target) else { throw BundledGrammarError.invalidResources }
            }
            guard target.standardizedFileURL.path.hasPrefix(canonicalRoot.path + "/"),
                  try regularSize(target) == record.bytes else { throw BundledGrammarError.invalidResources }
            let handle = try FileHandle(forReadingFrom: target)
            defer { try? handle.close() }
            var hash = SHA256(), read = 0
            // FileHandle bridges autoreleased NSData. Drain per read rather
            // than retaining the complete 337-MB resource set on the task's
            // thread until an unrelated outer pool happens to drain.
            while let bytes = try autoreleasepool(invoking: { try handle.read(upToCount: 1024 * 1024) }), !bytes.isEmpty {
                try Task.checkCancellation()
                guard bytes.count <= record.bytes - read else { throw BundledGrammarError.invalidResources }
                hash.update(data: bytes); read += bytes.count
            }
            guard read == record.bytes, hex(hash.finalize()) == record.sha256 else {
                throw BundledGrammarError.invalidResources
            }
            total += record.bytes
        }
        guard total == pin.bytes else { throw BundledGrammarError.invalidResources }
        return canonicalRoot
    }

    static func digest(_ data: Data) -> String { hex(SHA256.hash(data: data)) }
    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
    private static func isLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
    private static func isDirectory(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }
    private static func regularSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else { throw BundledGrammarError.invalidResources }
        return size
    }
}

#if canImport(ScriptumGrammar)
private struct InstalledGrammarEngine: BundledGrammarEngine {
    let resourceRoot: URL
    var languages: Set<String> { Set(BundledGrammarRuntime.languageCodes) }

    func check(text: String, language: String) throws -> Data {
        guard !Thread.isMainThread else { throw BundledGrammarError.nativeFailure(-1) }
        guard languages.contains(language) else { throw QualityError.unsupportedLanguage }
        guard text.utf8.count <= 100_000, !text.contains("\0") else { throw QualityError.inputTooLarge }
        var nativeThread: OpaquePointer?
        let created = graal_create_isolate(nil, nil, &nativeThread)
        guard created == 0, let thread = nativeThread else { throw BundledGrammarError.nativeFailure(created) }
        let result: Result<Data, Error> = Result {
            let heap = scriptum_quality_set_heap_limit(thread, 256 * 1024 * 1024)
            guard heap == 0 else { throw BundledGrammarError.nativeFailure(heap) }
            let root = resourceRoot.path
            let configured = root.withCString {
                scriptum_quality_set_resource_root(thread, UnsafeMutablePointer(mutating: $0), Int32(root.utf8.count))
            }
            guard configured == 0 else { throw BundledGrammarError.nativeFailure(configured) }
            var output = [CChar](repeating: 0, count: 2_000_000)
            let length = language.withCString { code in text.withCString { input in
                output.withUnsafeMutableBufferPointer { buffer in
                    scriptum_quality_check(thread, UnsafeMutablePointer(mutating: code), Int32(language.utf8.count),
                        UnsafeMutablePointer(mutating: input), Int32(text.utf8.count), buffer.baseAddress, Int32(buffer.count))
                }
            } }
            guard length > 0, length <= output.count else { throw BundledGrammarError.nativeFailure(length) }
            return Data(output.prefix(Int(length)).map { UInt8(bitPattern: $0) })
        }
        let teardown = graal_tear_down_isolate(thread)
        guard teardown == 0 else { throw BundledGrammarError.nativeFailure(teardown) }
        return try result.get()
    }
}
#endif
