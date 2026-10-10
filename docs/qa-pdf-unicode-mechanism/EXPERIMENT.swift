import Foundation
import CoreGraphics
import CoreText
import PDFKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func draw(_ text: String, font: String, x: CGFloat, context: CGContext) {
    let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, 18, nil)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    context.textPosition = CGPoint(x: x, y: 700)
    CTLineDraw(line, context)
}
for tagged in [false, true] {
    let file = folder.appendingPathComponent(tagged ? "tagged.pdf" : "plain.pdf")
    var box = CGRect(x: 0,y: 0,width: 595.28,height: 841.89)
    guard let context = CGContext(file as CFURL, mediaBox: &box, nil) else { fatalError("Context failed") }
    context.beginPDFPage(nil)
    if tagged { CGPDFContextBeginTag(context, .paragraph, [:] as CFDictionary) }
    draw("Vorher",font:"Georgia",x:72,context:context)
    if tagged { CGPDFContextBeginTag(context, .span, [CGPDFTagProperty.actualText: "🦊"] as CFDictionary) }
    draw("🦊",font:"AppleColorEmoji",x:155,context:context)
    if tagged { CGPDFContextEndTag(context) }
    draw("Nachher",font:"Georgia",x:190,context:context)
    if tagged { CGPDFContextEndTag(context) }
    context.endPDFPage(); context.closePDF()
    guard let pdf = PDFDocument(url:file) else { fatalError("Read failed") }
    print("\(tagged ? "tagged" : "plain"): \(String(reflecting: pdf.string))")
}
