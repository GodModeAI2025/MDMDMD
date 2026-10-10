import Foundation

/// Small portable ZIP32 writer. Every entry is stored (method zero), CRC checked
/// by readers. EPUB requires mimetype first, uncompressed and without extras.
struct StoredZIP {
    struct Entry { var name: String; var data: Data }
    static func archive(_ entries: [Entry]) throws -> Data {
        try Task.checkCancellation()
        guard entries.count <= Int(UInt16.max) else { throw ExportError.archiveTooLarge }
        var output = Data(), directory = Data(), names: Set<String> = []
        for entry in entries {
            try Task.checkCancellation()
            let name = Data(entry.name.utf8)
            guard names.insert(entry.name).inserted, name.count <= Int(UInt16.max), entry.data.count <= Int(UInt32.max), output.count <= Int(UInt32.max), !entry.name.hasPrefix("/"), !entry.name.split(separator: "/").contains("..") else { throw ExportError.archiveTooLarge }
            let offset = UInt32(output.count), size = UInt32(entry.data.count), crc = try crc32(entry.data)
            output.le(UInt32(0x04034b50)); output.le(UInt16(20)); output.le(UInt16(0x0800)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(0x0021)); output.le(crc); output.le(size); output.le(size); output.le(UInt16(name.count)); output.le(UInt16(0)); output.append(name); output.append(entry.data)
            directory.le(UInt32(0x02014b50)); directory.le(UInt16(20)); directory.le(UInt16(20)); directory.le(UInt16(0x0800)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0x0021)); directory.le(crc); directory.le(size); directory.le(size); directory.le(UInt16(name.count)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt32(0)); directory.le(offset); directory.append(name)
        }
        guard output.count <= Int(UInt32.max) - directory.count - 22, directory.count <= Int(UInt32.max) - 22 else { throw ExportError.archiveTooLarge }
        try Task.checkCancellation()
        let start = UInt32(output.count); output.append(directory); output.le(UInt32(0x06054b50)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(entries.count)); output.le(UInt16(entries.count)); output.le(UInt32(directory.count)); output.le(start); output.le(UInt16(0)); return output
    }
    static func crc32(_ data: Data) throws -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for (offset, byte) in data.enumerated() {
            if offset & 0xffff == 0 { try Task.checkCancellation() }
            crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
        return crc ^ 0xffffffff
    }
}
extension Data { mutating func le<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) } } }
