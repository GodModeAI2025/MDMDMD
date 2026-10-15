import Foundation
@testable import SkriptumWritingQuality

/// Exports exactly the app's submitted projection for independent JVM parity.
@main struct UpstreamProjectionExport {
    struct Corpus: Decodable { let records: [Record] }
    struct Record: Decodable { let language: String, source: String }
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw QualityError.invalidConfiguration }
            let corpus = try JSONDecoder().decode(Corpus.self,
                from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            var records: [[String: Any]] = []
            for record in corpus.records {
                let document = try await QualityDocument.prepare(source: record.source, revision: UUID())
                records.append(["language": record.language, "source": document.projection.text,
                                "response": ["matches": []]])
            }
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["records": records], options: [.sortedKeys]))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch { FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8)); exit(1) }
    }
}
