import Foundation
import Darwin

struct AdmissionDenialRecord: Codable {
    let origin: String; let profileID: String; let accountID: UUID
    let generation: UUID; let reason: WorkspaceCredentialDenialReason
    init(scope: WorkspaceCredentialScope, generation: UUID, reason: WorkspaceCredentialDenialReason) {
        origin = scope.origin.url.absoluteString; profileID = scope.profileID; accountID = scope.accountID
        self.generation = generation; self.reason = reason
    }
    var scope: WorkspaceCredentialScope {
        // Only validated records enter a ledger/context.
        try! validatedScope()
    }
    func validatedScope() throws -> WorkspaceCredentialScope {
        let parsed: WorkspaceOrigin
        if origin.hasPrefix("http:") { parsed = try WorkspaceOrigin.loopbackForTesting(origin) }
        else { parsed = try WorkspaceOrigin(origin) }
        guard parsed.url.absoluteString.utf8.elementsEqual(origin.utf8), origin.utf8.count <= 2048 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        return try WorkspaceCredentialScope(origin: parsed, profileID: profileID, accountID: accountID)
    }
}
struct AdmissionDenialLedger: Codable {
    var schemaVersion = 1
    var revision = UUID()
    var denials: [AdmissionDenialRecord] = []
}
struct AdmissionDenialSnapshot { let ledger: AdmissionDenialLedger; let bytes: Data? }
/// Own directory descriptor and final-file no-follow IO. No path resolution or
/// cross-process lock claim; expected exact bytes reject external replacement.
final class AdmissionDenialRepository: @unchecked Sendable {
    static let filename = "workspace-denials.json"
    let identity: String
    private let descriptor: Int32
    init(directory: URL) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/"), !directory.path.contains("//") else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        let pieces = directory.path.split(separator: "/").map(String.init)
        guard !pieces.isEmpty, pieces.allSatisfy({ $0 != "." && $0 != ".." }) else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw WorkspaceCredentialAdmissionError.persistenceUnavailable }
        for (index, piece) in pieces.enumerated() {
            var next = Darwin.openat(current, piece, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT, index == pieces.count - 1 {
                if Darwin.mkdirat(current, piece, 0o700) != 0, errno != EEXIST { Darwin.close(current); throw WorkspaceCredentialAdmissionError.persistenceUnavailable }
                next = Darwin.openat(current, piece, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            Darwin.close(current)
            guard next >= 0 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
            current = next
        }
        var info = stat()
        guard Darwin.fstat(current, &info) == 0, info.st_uid == getuid() else { Darwin.close(current); throw WorkspaceCredentialAdmissionError.invalidDenialState }
        descriptor = current; identity = "\(info.st_dev):\(info.st_ino)"
    }
    deinit { Darwin.close(descriptor) }
    func read() throws -> AdmissionDenialSnapshot {
        let fd = Darwin.openat(descriptor, Self.filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return AdmissionDenialSnapshot(ledger: AdmissionDenialLedger(), bytes: nil) }
        guard fd >= 0 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_size >= 1, info.st_size <= 262_144 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= 262_144 - data.count else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
            if count == 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
        do {
            var parser = try DenialJSONBoundary(data: data); try parser.validate()
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys) == ["schemaVersion", "revision", "denials"],
                  let rows = object["denials"] as? [[String: Any]], rows.count <= 1024,
                  rows.allSatisfy({ Set($0.keys) == ["origin", "profileID", "accountID", "generation", "reason"] }) else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
            let ledger = try JSONDecoder().decode(AdmissionDenialLedger.self, from: data)
            guard ledger.schemaVersion == 1 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
            var scopes: Set<WorkspaceCredentialScope> = []
            for record in ledger.denials { guard scopes.insert(try record.validatedScope()).inserted else { throw WorkspaceCredentialAdmissionError.invalidDenialState } }
            return AdmissionDenialSnapshot(ledger: ledger, bytes: data)
        } catch { throw WorkspaceCredentialAdmissionError.invalidDenialState }
    }
    func write(_ proposed: AdmissionDenialLedger, expected: Data?) throws -> AdmissionDenialSnapshot {
        guard proposed.denials.count <= 1024 else { throw WorkspaceCredentialAdmissionError.capacityExceeded }
        guard try read().bytes == expected else { throw WorkspaceCredentialAdmissionError.staleTicket }
        var candidate = proposed; candidate.revision = UUID()
        candidate.denials.sort { ($0.origin, $0.profileID, $0.accountID.uuidString) < ($1.origin, $1.profileID, $1.accountID.uuidString) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(candidate)
        guard bytes.count <= 262_144 else { throw WorkspaceCredentialAdmissionError.capacityExceeded }
        let name = ".denial-" + UUID().uuidString
        let fd = Darwin.openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw WorkspaceCredentialAdmissionError.persistenceUnavailable }
        defer { Darwin.close(fd); Darwin.unlinkat(descriptor, name, 0) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw WorkspaceCredentialAdmissionError.persistenceUnavailable }; offset += count
            }
        }
        guard Darwin.fsync(fd) == 0, Darwin.renameat(descriptor, name, descriptor, Self.filename) == 0,
              Darwin.fsync(descriptor) == 0 else { throw WorkspaceCredentialAdmissionError.persistenceUnavailable }
        return AdmissionDenialSnapshot(ledger: candidate, bytes: bytes)
    }
}
/// File grammar adds arrays to the wire parser's strict object/scalar contract;
/// bounded byte/node limits prevent permissive JSONDecoder duplicate-key folding.
private struct DenialJSONBoundary {
    let bytes: [UInt8]; var position = 0; var nodes = 0
    init(data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        bytes = Array(data)
    }
    mutating func validate() throws { try value(0); space(); guard position == bytes.count else { throw WorkspaceCredentialAdmissionError.invalidDenialState } }
    mutating func space() { while position < bytes.count, [9, 10, 13, 32].contains(bytes[position]) { position += 1 } }
    mutating func string() throws -> String {
        guard position < bytes.count, bytes[position] == 34 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        let start = position; position += 1; var escaped = false
        while position < bytes.count {
            let byte = bytes[position]; position += 1
            if byte == 34 && !escaped {
                guard let string = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<position])), string.utf8.count <= 2048 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
                return string
            }
            if byte == 92 && !escaped { escaped = true } else { escaped = false }
        }
        throw WorkspaceCredentialAdmissionError.invalidDenialState
    }
    mutating func value(_ depth: Int) throws {
        nodes += 1; guard depth <= 4, nodes <= 16_384 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        space(); guard position < bytes.count else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
        if bytes[position] == 34 { _ = try string(); return }
        if bytes[position] == 123 || bytes[position] == 91 {
            let object = bytes[position] == 123, close: UInt8 = object ? 125 : 93
            position += 1; space(); var keys: Set<String> = []
            if position < bytes.count, bytes[position] == close { position += 1; return }
            while position < bytes.count {
                if object { space(); let key = try string(); guard keys.insert(key).inserted else { throw WorkspaceCredentialAdmissionError.invalidDenialState }; space(); guard position < bytes.count, bytes[position] == 58 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }; position += 1 }
                try value(depth + 1); space(); guard position < bytes.count else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
                let delimiter = bytes[position]; position += 1
                if delimiter == close { return }; guard delimiter == 44 else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
            }
            throw WorkspaceCredentialAdmissionError.invalidDenialState
        }
        let start = position
        while position < bytes.count, ![9, 10, 13, 32, 44, 125, 93].contains(bytes[position]) { position += 1 }
        let token = String(decoding: bytes[start..<position], as: UTF8.self)
        guard ["true", "false", "null"].contains(token) || token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw WorkspaceCredentialAdmissionError.invalidDenialState }
    }
}
