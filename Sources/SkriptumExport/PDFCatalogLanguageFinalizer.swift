import Foundation
import CoreGraphics

/// A narrow incremental catalog update for our finalized Quartz output. Original
/// streams, object offsets and trailer metadata remain byte-for-byte intact.
enum PDFCatalogLanguageFinalizer {
    enum Failure: Error { case invalidLanguage, unsupportedPDF }
    static func languageTag(_ source: String?) throws -> String? {
        guard let source else { return nil }
        let tag = source.replacingOccurrences(of: "_", with: "-")
        guard !tag.isEmpty, tag.utf8.count <= 255, tag.utf8.allSatisfy({ $0 < 128 }) else { throw Failure.invalidLanguage }
        let old: Set<String> = ["en-gb-oed", "i-ami", "i-bnn", "i-default", "i-enochian", "i-hak", "i-klingon", "i-lux", "i-mingo", "i-navajo", "i-pwn", "i-tao", "i-tay", "i-tsu", "sgn-be-fr", "sgn-be-nl", "sgn-ch-de", "art-lojban", "cel-gaulish", "no-bok", "no-nyn", "zh-guoyu", "zh-hakka", "zh-min", "zh-min-nan", "zh-xiang"]
        let regular = "(?:[A-Za-z]{2,3}(?:-[A-Za-z]{3}){0,3}|[A-Za-z]{4}|[A-Za-z]{5,8})(?:-[A-Za-z]{4})?(?:-(?:[A-Za-z]{2}|[0-9]{3}))?(?:-(?:[A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3}))*(?:-[0-9A-WY-Za-wy-z](?:-[A-Za-z0-9]{2,8})+)*(?:-[xX](?:-[A-Za-z0-9]{1,8})+)?"
        let pattern = "\\A(?:" + regular + "|[xX](?:-[A-Za-z0-9]{1,8})+)\\z"
        guard old.contains(tag.lowercased()) || tag.range(of: pattern, options: .regularExpression) != nil else { throw Failure.invalidLanguage }
        let parts = tag.split(separator: "-").map(String.init)
        if !old.contains(tag.lowercased()), parts[0].lowercased() != "x" {
            var singletons: Set<String> = [], variants: Set<String> = [], inExtension = false
            for part in parts.dropFirst() {
                let lower = part.lowercased()
                if lower == "x" { break }
                if part.count == 1 {
                    guard singletons.insert(lower).inserted else { throw Failure.invalidLanguage }
                    inExtension = true
                } else if !inExtension, part.count >= 5 || (part.count == 4 && part.first?.isNumber == true) {
                    guard variants.insert(lower).inserted else { throw Failure.invalidLanguage }
                }
            }
        }
        var afterSingleton = false
        return parts.enumerated().map { index, part in
            var value = part.lowercased()
            if index > 0, !afterSingleton {
                if part.count == 2 { value = part.uppercased() }
                else if part.count == 4 { value = value.prefix(1).uppercased() + value.dropFirst() }
            }
            if part.count == 1 { afterSingleton = true }
            return value
        }.joined(separator: "-")
    }
    static func add(_ source: String?, to data: Data) throws -> Data {
        guard let tag = try languageTag(source) else { return data }
        try Task.checkCancellation()
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider), let catalog = document.catalog else { throw Failure.unsupportedPDF }
        var type: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(catalog, "Type", &type), let type, String(cString: type) == "Catalog" else { throw Failure.unsupportedPDF }
        var existing: CGPDFStringRef?
        if CGPDFDictionaryGetString(catalog, "Lang", &existing), let existing,
           let value = CGPDFStringCopyTextString(existing) as String?, value.lowercased() == tag.lowercased() { return data }
        var object: CGPDFObjectRef?
        guard !CGPDFDictionaryGetObject(catalog, "Lang", &object) else { throw Failure.unsupportedPDF }
        let bytes = [UInt8](data)
        guard let marker = data.range(of: Data("startxref\n".utf8), options: .backwards),
              let number = String(decoding: data[marker.upperBound...], as: UTF8.self).split(separator: "\n").first,
              let xref = Int(number), xref >= 0, xref < bytes.count else { throw Failure.unsupportedPDF }
        var cursor = xref
        func line() throws -> String {
            guard cursor < bytes.count, let end = bytes[cursor...].firstIndex(of: 10) else { throw Failure.unsupportedPDF }
            defer { cursor = end + 1 }
            return String(decoding: bytes[cursor..<end], as: UTF8.self)
        }
        guard try line() == "xref" else { throw Failure.unsupportedPDF }
        let range = try line().split(separator: " ")
        guard range.count == 2, range[0] == "0", let count = Int(range[1]), count > 0,
              count <= (bytes.count - cursor) / 20 else { throw Failure.unsupportedPDF }
        var entries: [(Int, Int, Bool)] = []
        for _ in 0..<count {
            try Task.checkCancellation()
            let start = cursor, fields = try line().split(separator: " ")
            guard cursor - start == 20, fields.count == 3,
                  let offset = Int(fields[0]), let generation = Int(fields[1]),
                  fields[2] == "n" || fields[2] == "f" else { throw Failure.unsupportedPDF }
            entries.append((offset, generation, fields[2] == "n"))
        }
        guard try line() == "trailer" else { throw Failure.unsupportedPDF }
        let trailer = try dictionary(bytes, start: cursor, limit: bytes.count)
        let trailerText = String(decoding: bytes[trailer], as: UTF8.self)
        guard !trailerText.contains("/Prev"), !trailerText.contains("/XRefStm"), !trailerText.contains("/Encrypt") else { throw Failure.unsupportedPDF }
        let rootPattern = try NSRegularExpression(pattern: "/Root[ \\t\\r\\n]+([0-9]+)[ \\t\\r\\n]+([0-9]+)[ \\t\\r\\n]+R(?=[ \\t\\r\\n<>])")
        guard let match = rootPattern.firstMatch(in: trailerText, range: NSRange(trailerText.startIndex..., in: trailerText)),
              let objectRange = Range(match.range(at: 1), in: trailerText), let generationRange = Range(match.range(at: 2), in: trailerText),
              let root = Int(trailerText[objectRange]), let generation = Int(trailerText[generationRange]),
              root > 0, root < entries.count, generation >= 0, generation <= 65535, entries[root].2, entries[root].1 == generation else { throw Failure.unsupportedPDF }
        let start = entries[root].0, header = Array("\(root) \(generation) obj".utf8)
        guard start > 0, start <= xref - header.count, Array(bytes[start..<(start + header.count)]) == header else { throw Failure.unsupportedPDF }
        let end = entries.filter { $0.2 && $0.0 > start }.map(\.0).min() ?? xref
        let body = try dictionary(bytes, start: start + header.count, limit: end)
        var major: Int32 = 0, minor: Int32 = 0
        document.getVersion(majorVersion: &major, minorVersion: &minor)
        var version: UnsafePointer<CChar>?
        let hasVersion = CGPDFDictionaryGetName(catalog, "Version", &version)
        var versionObject: CGPDFObjectRef?
        guard !CGPDFDictionaryGetObject(catalog, "Version", &versionObject) || hasVersion else { throw Failure.unsupportedPDF }
        let catalogVersion = version.map { Double(String(cString: $0)) } ?? nil
        let needsVersion = major < 1 || (major == 1 && minor < 4)
        guard !needsVersion || !hasVersion || (catalogVersion ?? 0) >= 1.4 else { throw Failure.unsupportedPDF }
        let minimumVersion = needsVersion && !hasVersion ? " /Version /1.4" : ""
        let encoded = tag.utf8.map { String(format: "%02X", $0) }.joined()
        var result = data; result.append(Data("\n".utf8))
        let newObject = result.count
        result.append(Data("\(root) \(generation) obj\n".utf8))
        result.append(Data(bytes[body.lowerBound..<(body.upperBound - 2)]))
        result.append(Data("\n/Lang <\(encoded)>\(minimumVersion)\n>>\nendobj\n".utf8))
        let newXref = result.count
        result.append(Data("xref\n0 \(entries.count)\n".utf8))
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let offset = index == root ? newObject : entry.0
            result.append(Data(String(format: "%010lld %05d %@ \n", Int64(offset), entry.1, entry.2 ? "n" : "f").utf8))
        }
        result.append(Data("trailer\n".utf8))
        result.append(Data(bytes[trailer.lowerBound..<(trailer.upperBound - 2)]))
        result.append(Data("\n/Prev \(xref)\n>>\nstartxref\n\(newXref)\n%%EOF\n".utf8))
        try Task.checkCancellation()
        return result
    }
    private static func dictionary(_ bytes: [UInt8], start: Int, limit: Int) throws -> Range<Int> {
        guard start >= 0, limit <= bytes.count, start < limit else { throw Failure.unsupportedPDF }
        var i = start
        while i < limit {
            if [0, 9, 10, 12, 13, 32].contains(bytes[i]) { i += 1 }
            else if bytes[i] == 37 { while i < limit && bytes[i] != 10 && bytes[i] != 13 { i += 1 } }
            else { break }
        }
        guard i + 1 < limit, bytes[i] == 60, bytes[i + 1] == 60 else { throw Failure.unsupportedPDF }
        let first = i; var depth = 0
        while i < limit {
            if i & 4095 == 0 { try Task.checkCancellation() }
            if bytes[i] == 37 { while i < limit && bytes[i] != 10 && bytes[i] != 13 { i += 1 } }
            else if bytes[i] == 40 {
                i += 1; var strings = 1
                while i < limit && strings > 0 {
                    if bytes[i] == 92 { i += 2; continue }
                    if bytes[i] == 40 { strings += 1 }
                    if bytes[i] == 41 { strings -= 1 }
                    i += 1
                }
                guard strings == 0 else { throw Failure.unsupportedPDF }
            } else if bytes[i] == 60 {
                if i + 1 < limit && bytes[i + 1] == 60 { depth += 1; i += 2 }
                else {
                    i += 1; while i < limit && bytes[i] != 62 { i += 1 }
                    guard i < limit else { throw Failure.unsupportedPDF }; i += 1
                }
            } else if bytes[i] == 62, i + 1 < limit, bytes[i + 1] == 62 {
                depth -= 1; i += 2
                if depth == 0 { return first..<i }
            } else { i += 1 }
        }
        throw Failure.unsupportedPDF
    }
}
