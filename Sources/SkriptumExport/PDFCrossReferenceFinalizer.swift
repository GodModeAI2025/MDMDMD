import Foundation

/// Corrects absent, unreferenced zero-offset entries emitted by Quartz. Only
/// fixed-size classic xref entries change; streams and all offsets stay intact.
/// This is deliberately not an imported-PDF repair or general PDF parser.
enum PDFCrossReferenceFinalizer {
    enum ValidationError: Error { case unsupportedStructure, invalidEntry, referencedMissingObject }
    static func finalize(_ data: Data) throws -> Data {
        try Task.checkCancellation()
        let bytes = [UInt8](data)
        guard let marker = data.range(of: Data("startxref\n".utf8), options: .backwards) else {
            throw ValidationError.unsupportedStructure
        }
        let tail = String(decoding: data[marker.upperBound...], as: UTF8.self)
        guard let number = tail.split(separator: "\n").first, let offset = Int(number),
              offset >= 0, offset < bytes.count else { throw ValidationError.unsupportedStructure }
        var position = offset
        func line() throws -> String {
            guard position < bytes.count, let end = bytes[position...].firstIndex(of: 10) else {
                throw ValidationError.unsupportedStructure
            }
            defer { position = end + 1 }
            return String(decoding: bytes[position..<end], as: UTF8.self)
        }
        guard try line() == "xref" else { throw ValidationError.unsupportedStructure }
        let subsection = try line().split(separator: " ")
        guard subsection.count == 2, subsection[0] == "0", let count = Int(subsection[1]),
              count > 0, count <= (bytes.count - position) / 20 else { throw ValidationError.unsupportedStructure }
        let tableStart = position
        var missing: [Int] = [], objectStarts: [Int] = []
        for object in 0..<count {
            if object & 1023 == 0 { try Task.checkCancellation() }
            let entryStart = position
            let entry = try line()
            guard position - entryStart == 20 else { throw ValidationError.invalidEntry }
            let fields = entry.split(separator: " ")
            guard fields.count == 3, fields[0].count == 10, fields[1].count == 5,
                  let address = Int(fields[0]), let generation = Int(fields[1]),
                  fields[2] == "n" || fields[2] == "f" else { throw ValidationError.invalidEntry }
            if fields[2] == "n" {
                if address == 0 { missing.append(object) }
                else {
                    objectStarts.append(address)
                    let prefix = Array("\(object) \(generation) obj".utf8)
                    guard address > 0, address <= bytes.count - prefix.count,
                          Array(bytes[address..<(address + prefix.count)]) == prefix else {
                        throw ValidationError.invalidEntry
                    }
                }
            } else if object == 0 {
                guard address == 0, generation == 65535 else { throw ValidationError.unsupportedStructure }
            }
        }
        let trailer = String(decoding: bytes[position...], as: UTF8.self)
        guard trailer.hasPrefix("trailer\n"), !trailer.contains("/Prev"), !trailer.contains("/XRefStm"),
              !trailer.contains("/Encrypt") else { throw ValidationError.unsupportedStructure }
        guard !missing.isEmpty else {
            return try PDFStructureAttributeNormalizer.normalize(data, objectStarts: objectStarts, xrefOffset: offset)
        }
        // A conservative raw-byte scan may reject an accidental match inside a
        // stream. It never frees an entry whose reference cannot be ruled out.
        let raw = String(decoding: bytes, as: UTF8.self)
        guard !raw.contains("/ObjStm"), !raw.contains("/ByteRange") else { throw ValidationError.unsupportedStructure }
        var result = data
        for object in missing {
            try Task.checkCancellation()
            let reference = try NSRegularExpression(pattern: "(?<![0-9])\(object)[ \\t\\r\\n]+[0-9]+[ \\t\\r\\n]+(?:R|obj)(?![A-Za-z])")
            guard reference.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) == nil else {
                throw ValidationError.referencedMissingObject
            }
            // PDF1.7 permits permanently free entries outside the linked free
            // list when they link to zero and have generation65535.
            let start = tableStart + object * 20
            result.replaceSubrange(start..<(start + 20), with: Data("0000000000 65535 f \n".utf8))
        }
        return try PDFStructureAttributeNormalizer.normalize(result, objectStarts: objectStarts, xrefOffset: offset)
    }
}
