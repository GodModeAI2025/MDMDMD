import Foundation
import AppKit
import PDFKit
let args = CommandLine.arguments
let pdf = PDFDocument(url: URL(fileURLWithPath: args[1]))!
let index = Int(args[2])!
let image = pdf.page(at: index)!.thumbnail(of: NSSize(width: 1200, height: 1600), for: .mediaBox)
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("PDFKit page \(index+1)/\(pdf.pageCount) rendered")
