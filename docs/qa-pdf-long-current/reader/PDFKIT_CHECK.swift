import Foundation
import PDFKit
let file = URL(fileURLWithPath: CommandLine.arguments[1])
guard let pdf = PDFDocument(url: file), let text = pdf.string else { fatalError("PDF read failed") }
let result: [String: Any] = ["reader":"macOS PDFKit", "pages": pdf.pageCount, "foxCount":text.components(separatedBy:"🦊").count-1,"repeatedParagraphCount":text.components(separatedBy:"Absatz des langen Manuskripts: Quellen, Gedanken und eine präzise Frage.").count-1]
print(String(data:try JSONSerialization.data(withJSONObject: result, options:[.prettyPrinted,.sortedKeys]), encoding:.utf8)!)
