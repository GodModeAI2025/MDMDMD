import Foundation

enum ProbeError: Error {
    case createIsolate(Int32), nativeResponse(String, Int32), invalidResponse, missingExpectedRule(String, String)
}

func checkedResponse(_ language: String, _ text: String, thread: OpaquePointer) throws -> [String: Any] {
    guard !language.isEmpty, language.utf8.count <= 32, text.utf8.count <= 100_000 else { throw ProbeError.invalidResponse }
    var languageBytes = language.utf8.map { CChar(bitPattern: $0) }
    var textBytes = text.utf8.map { CChar(bitPattern: $0) }
    let textLength = textBytes.count
    if textBytes.isEmpty { textBytes.append(0) }
    var output = [CChar](repeating: 0, count: 2_000_000)
    let result = languageBytes.withUnsafeMutableBufferPointer { languageBuffer in
        textBytes.withUnsafeMutableBufferPointer { textBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                scriptum_quality_check(thread, languageBuffer.baseAddress, Int32(languageBuffer.count),
                    textBuffer.baseAddress, Int32(textLength), outputBuffer.baseAddress, Int32(outputBuffer.count))
            }
        }
    }
    guard result >= 0, result <= output.count else { throw ProbeError.nativeResponse(language, result) }
    guard Array(languageBytes).map({ UInt8(bitPattern: $0) }) == Array(language.utf8),
          Array(textBytes.prefix(textLength)).map({ UInt8(bitPattern: $0) }) == Array(text.utf8) else {
        throw ProbeError.invalidResponse
    }
    let data = Data(output.prefix(Int(result)).map { UInt8(bitPattern: $0) })
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          value["matches"] is [[String: Any]] else { throw ProbeError.invalidResponse }
    return value
}

var nativeThread: OpaquePointer?
let creation = graal_create_isolate(nil, nil, &nativeThread)
guard creation == 0, let thread = nativeThread else { throw ProbeError.createIsolate(creation) }
defer { _ = graal_tear_down_isolate(thread) }
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let corpus = try JSONSerialization.jsonObject(with: input) as? [String: Any],
      let records = corpus["records"] as? [[String: Any]] else { throw ProbeError.invalidResponse }
var results: [[String: Any]] = []
for record in records {
    guard let language = record["language"] as? String, let source = record["source"] as? String,
          let expected = record["response"] as? [String: Any],
          let matches = expected["matches"] as? [[String: Any]] else { throw ProbeError.invalidResponse }
    let start = Date()
    let response = try checkedResponse(language, source, thread: thread)
    guard let actual = response["matches"] as? [[String: Any]] else { throw ProbeError.invalidResponse }
    let ruleIDs = Set(actual.compactMap { ($0["rule"] as? [String: Any])?["id"] as? String })
    for match in matches {
        guard let rule = (match["rule"] as? [String: Any])?["id"] as? String else { throw ProbeError.invalidResponse }
        guard ruleIDs.contains(rule) else { throw ProbeError.missingExpectedRule(language, rule) }
    }
    if let absent = record["absentRuleIDs"] as? [String] {
        guard absent.allSatisfy({ !ruleIDs.contains($0) }) else { throw ProbeError.invalidResponse }
    }
    results.append(["language": language, "elapsedMillis": Int(Date().timeIntervalSince(start) * 1_000), "response": response])
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
