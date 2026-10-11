import Foundation
import Testing
@testable import SkriptumExport

@Test func figureAttributeNormalizationLeavesLiteralsNestedKeysAndStreamsUntouched() throws {
    let objects = [
        "1 0 obj\n<< /S /Figure /AltText (Literal /AltText (nested) \\) text) /Nested << /AltText (keep) >> >>\nendobj\n",
        "2 0 obj\n<< /S /P /AltText (keep) >>\nendobj\n",
        "3 0 obj\n<< /S /Figure /AltText (keep) >>\nstream\n/AltText binary\nendstream\nendobj\n"
    ]
    let source = objects.joined(), data = Data(source.utf8)
    let starts = [0, objects[0].utf8.count, objects[0].utf8.count + objects[1].utf8.count]
    let normalized = try PDFStructureAttributeNormalizer.normalize(data, objectStarts: starts, xrefOffset: data.count)
    let text = String(decoding: normalized, as: UTF8.self)
    #expect(normalized.count == data.count)
    #expect(text.hasPrefix("1 0 obj\n<< /S /Figure /Alt     (Literal /AltText"))
    #expect(text.contains("/Nested << /AltText (keep) >>"))
    #expect(text.contains(objects[1]))
    #expect(text.contains(objects[2]))
    #expect(try PDFStructureAttributeNormalizer.normalize(normalized, objectStarts: starts, xrefOffset: data.count) == normalized)
}
