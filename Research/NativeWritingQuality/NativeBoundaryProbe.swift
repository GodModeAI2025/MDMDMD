import Foundation

enum BoundaryFailure: Error { case contract(String) }
func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw BoundaryFailure.contract(name) }
}

var nativeThread: OpaquePointer?
try require(graal_create_isolate(nil, nil, &nativeThread) == 0, "create isolate")
guard let thread = nativeThread else { throw BoundaryFailure.contract("missing thread") }
defer { _ = graal_tear_down_isolate(thread) }

var checks: [String] = []
var exhaustHeap = false
var resourceRoot: String?
for option in CommandLine.arguments.dropFirst() {
    if option == "--heap-exhaustion", !exhaustHeap { exhaustHeap = true }
    else if option.hasPrefix("--resource-root="), resourceRoot == nil { resourceRoot = String(option.dropFirst("--resource-root=".count)) }
    else { throw BoundaryFailure.contract("invalid probe mode") }
}
try require(scriptum_quality_set_heap_limit(thread, 0) == -1, "reject zero heap")
checks.append("reject zero heap")
try require(scriptum_quality_set_heap_limit(thread, 513 * 1024 * 1024) == -1, "reject oversized heap")
checks.append("reject oversized heap")
try require(scriptum_quality_set_heap_limit(thread, exhaustHeap ? 128 * 1024 * 1024 : 256 * 1024 * 1024) == 0, "configure bounded heap")
checks.append("configure bounded heap")
try require(scriptum_quality_set_resource_root(thread, nil, 1) == -1, "reject null resource root")
checks.append("reject null resource root")
if let resourceRoot {
    let result = resourceRoot.withCString { scriptum_quality_set_resource_root(thread, UnsafeMutablePointer(mutating: $0), Int32(resourceRoot.utf8.count)) }
    try require(result == 0, "configure external resource root")
    checks.append("configure external resource root")
}
for (name, value, expected) in [
    ("reject empty resource root", "", Int32(-1)),
    ("reject relative resource root", "relative/resource-root", Int32(-2)),
    ("reject NUL resource root", "/invalid\0resource-root", Int32(-2))
] {
    let result = value.withCString { scriptum_quality_set_resource_root(thread, UnsafeMutablePointer(mutating: $0), Int32(value.utf8.count)) }
    try require(result == expected, name); checks.append(name)
}

func call(language: [CChar] = Array("en".utf8).map { CChar(bitPattern: $0) },
          text: [CChar] = Array("A short sentence.".utf8).map { CChar(bitPattern: $0) },
          languageLength: Int32? = nil, textLength: Int32? = nil,
          capacity: Int32 = 2_000_000, nullLanguage: Bool = false,
          nullText: Bool = false, nullOutput: Bool = false) throws -> (Int32, Data) {
    let languageCount = languageLength ?? Int32(language.count)
    let textCount = textLength ?? Int32(text.count)
    var languageBytes = language.isEmpty ? [0] : language
    var textBytes = text.isEmpty ? [0] : text
    let originalLanguage = languageBytes, originalText = textBytes
    // Prefix and suffix canaries surround the declared output capacity.
    var output = [CChar](repeating: 90, count: 2_000_032)
    let result = languageBytes.withUnsafeMutableBufferPointer { languageBuffer in
        textBytes.withUnsafeMutableBufferPointer { textBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                scriptum_quality_check(thread, nullLanguage ? nil : languageBuffer.baseAddress, languageCount,
                    nullText ? nil : textBuffer.baseAddress, textCount,
                    nullOutput ? nil : outputBuffer.baseAddress?.advanced(by: 16), capacity)
            }
        }
    }
    try require(languageBytes == originalLanguage && textBytes == originalText, "input buffers unchanged")
    try require(output.prefix(16).allSatisfy { $0 == 90 } && output.suffix(16).allSatisfy { $0 == 90 }, "output canaries")
    if result < 0 {
        try require(output.allSatisfy { $0 == 90 }, "no partial output on error")
        return (result, Data())
    }
    try require(result <= capacity && result <= 2_000_000, "output length within capacity")
    try require(output.dropFirst(16 + Int(result)).allSatisfy { $0 == 90 }, "output stops at returned length")
    return (result, Data(output[16..<(16 + Int(result))].map { UInt8(bitPattern: $0) }))
}

if exhaustHeap {
    let result = try call(language: Array("de".utf8).map { CChar(bitPattern: $0) },
        text: Array("Das ist zwingendermaßen nicht erforderlich.".utf8).map { CChar(bitPattern: $0) })
    try require(result.0 == -5, "heap exhaustion returns explicit error with untouched buffers")
    checks.append("heap exhaustion returns explicit error with untouched buffers")
    // No further native call is made; the defer tears this isolate down.
} else {
    for (name, result, expected) in [
        ("null language", try call(nullLanguage: true).0, Int32(-1)),
        ("null text", try call(nullText: true).0, Int32(-1)),
        ("null output", try call(nullOutput: true).0, Int32(-1)),
        ("oversized language length", try call(languageLength: 33).0, Int32(-1)),
        ("oversized text length", try call(textLength: 100_001).0, Int32(-1)),
        ("negative output capacity", try call(capacity: -1).0, Int32(-1)),
        ("oversized output capacity", try call(capacity: 2_000_001).0, Int32(-1)),
        ("malformed UTF-8", try call(text: [CChar(bitPattern: 0xc3), 0x28]).0, Int32(-2)),
        ("embedded NUL", try call(text: [65, 0, 66]).0, Int32(-2)),
        ("unsupported language", try call(language: Array("invalid-language".utf8).map { CChar(bitPattern: $0) }).0, Int32(-2)),
        ("zero output capacity", try call(capacity: 0).0, Int32(-4))
    ] {
        try require(result == expected, name)
        checks.append(name)
    }
    
    let source = "🦊 The unicode standard defines almost 150,000 characters."
    let (length, data) = try call(text: source.utf8.map { CChar(bitPattern: $0) })
    try require(length > 0, "valid Unicode response")
    guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let matches = response["matches"] as? [[String: Any]] else {
        throw BoundaryFailure.contract("JSON matches")
    }
    try require(matches.contains {
        ($0["rule"] as? [String: Any])?["id"] as? String == "UNICODE_CASING" &&
        $0["offset"] as? Int == 7 && $0["length"] as? Int == 7
    }, "UTF-16 range after emoji")
    checks.append("UTF-16 range after emoji")
    try require(scriptum_quality_set_heap_limit(thread, 128 * 1024 * 1024) == -1, "reject reconfiguration after review")
    checks.append("reject reconfiguration after review")
    let rootChange = "/invalid-resource-root".withCString { scriptum_quality_set_resource_root(thread, UnsafeMutablePointer(mutating: $0), 22) }
    try require(rootChange == -1, "reject resource-root changes after review")
    checks.append("reject resource-root changes after review")
}

let receipt: [String: Any] = ["passed": true, "checks": checks, "network": "denied externally by sandbox-exec",
    "scope": "Native C ABI only; not app integration or iOS execution"]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]))
FileHandle.standardOutput.write(Data("\n".utf8))
