import ScriptumGrammar
import Foundation

enum ProbeError: Error {
    case createIsolate(Int32), heapConfiguration(Int32), resourceConfiguration(Int32), nativeResponse(String, Int32), invalidResponse, missingExpectedMatch(String, String, Int, Int)
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

func runCorpus() throws {
    guard (2...5).contains(CommandLine.arguments.count) else { throw ProbeError.invalidResponse }
    var isolatePerRecord = false
    var heapMegabytes: Int?
    var resourceRoot: String?
    for option in CommandLine.arguments.dropFirst(2) {
        if option == "--isolate-per-record", !isolatePerRecord { isolatePerRecord = true }
        else if option.hasPrefix("--heap-mb="), heapMegabytes == nil,
                let megabytes = Int(option.dropFirst("--heap-mb=".count)), (64...512).contains(megabytes) {
            heapMegabytes = megabytes
        } else if option.hasPrefix("--resource-root="), resourceRoot == nil {
            resourceRoot = String(option.dropFirst("--resource-root=".count))
        } else { throw ProbeError.invalidResponse }
    }
    func withIsolate<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var nativeThread: OpaquePointer?
        let creation = graal_create_isolate(nil, nil, &nativeThread)
        guard creation == 0, let thread = nativeThread else { throw ProbeError.createIsolate(creation) }
        defer { _ = graal_tear_down_isolate(thread) }
        if let heapMegabytes {
            let result = scriptum_quality_set_heap_limit(thread, Int64(heapMegabytes) * 1024 * 1024)
            guard result == 0 else { throw ProbeError.heapConfiguration(result) }
        }
        if let resourceRoot {
            guard resourceRoot.utf8.count <= 4096 else { throw ProbeError.invalidResponse }
            let result = resourceRoot.withCString { scriptum_quality_set_resource_root(thread, UnsafeMutablePointer(mutating: $0), Int32(resourceRoot.utf8.count)) }
            guard result == 0 else { throw ProbeError.resourceConfiguration(result) }
        }
        return try body(thread)
    }
    let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard let corpus = try JSONSerialization.jsonObject(with: input) as? [String: Any],
          let records = corpus["records"] as? [[String: Any]], records.count <= 100 else { throw ProbeError.invalidResponse }
    var results: [[String: Any]] = []
    func checkRecord(_ record: [String: Any], thread: OpaquePointer) throws -> [String: Any] {
        guard let language = record["language"] as? String, let source = record["source"] as? String,
              let expected = record["response"] as? [String: Any],
              let matches = expected["matches"] as? [[String: Any]] else { throw ProbeError.invalidResponse }
        let start = Date()
        let response = try checkedResponse(language, source, thread: thread)
        guard let actual = response["matches"] as? [[String: Any]] else { throw ProbeError.invalidResponse }
        // LanguageTool ranges use UTF-16, matching the unchanged editor source.
        for match in actual {
            guard let offset = match["offset"] as? Int, let length = match["length"] as? Int,
                  offset >= 0, length >= 0, offset <= source.utf16.count,
                  length <= source.utf16.count - offset else { throw ProbeError.invalidResponse }
        }
        let ruleIDs = Set(actual.compactMap { ($0["rule"] as? [String: Any])?["id"] as? String })
        for match in matches {
            guard let rule = (match["rule"] as? [String: Any])?["id"] as? String,
                  let offset = match["offset"] as? Int, let length = match["length"] as? Int else { throw ProbeError.invalidResponse }
            guard actual.contains(where: {
                ($0["rule"] as? [String: Any])?["id"] as? String == rule &&
                $0["offset"] as? Int == offset && $0["length"] as? Int == length
            }) else { throw ProbeError.missingExpectedMatch(language, rule, offset, length) }
        }
        if let absent = record["absentRuleIDs"] as? [String] {
            guard absent.allSatisfy({ !ruleIDs.contains($0) }) else { throw ProbeError.invalidResponse }
        }
        return ["language": language, "elapsedMillis": Int(Date().timeIntervalSince(start) * 1_000), "response": response]
    }
    if isolatePerRecord {
        for record in records {
            results.append(try withIsolate { try checkRecord(record, thread: $0) })
        }
    } else {
        try withIsolate { thread in
            for record in records { results.append(try checkRecord(record, thread: thread)) }
        }
    }
    let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

do { try runCorpus() }
catch {
    let value: [String: Any] = ["passed": false, "error": String(describing: error)]
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        FileHandle.standardError.write(data); FileHandle.standardError.write(Data("\n".utf8))
    }
    exit(1)
}
