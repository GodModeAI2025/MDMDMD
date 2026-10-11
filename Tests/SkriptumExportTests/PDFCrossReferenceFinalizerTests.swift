import Foundation
import Testing
@testable import SkriptumExport

@Test func crossReferenceFinalizationChangesOnlyUnusedEntryAndRejectsReference() throws {
    func fixture(reference: Bool) -> Data {
        var source = "%PDF-1.4\n1 0 obj\n<<" + (reference ? "/Other 2 0 R" : "") + ">>\nendobj\n"
        let offset = source.utf8.count
        source += "xref\n0 3\n0000000000 65535 f \n0000000009 00000 n \n0000000000 00000 n \ntrailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n\(offset)\n%%EOF\n"
        return Data(source.utf8)
    }
    let before = fixture(reference: false)
    let after = try PDFCrossReferenceFinalizer.finalize(before)
    #expect(before.count == after.count)
    #expect(String(decoding: after, as: UTF8.self).contains("0000000000 65535 f \ntrailer"))
    #expect(try PDFCrossReferenceFinalizer.finalize(after) == after)
    #expect(throws: PDFCrossReferenceFinalizer.ValidationError.referencedMissingObject) {
        try PDFCrossReferenceFinalizer.finalize(fixture(reference: true))
    }
}
