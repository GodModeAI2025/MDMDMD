import Foundation
import PDFKit
import AppKit
let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let p = document.page(at: 1)!
let image = p.thumbnail(of: NSSize(width: 778,height:1100), for: .mediaBox)
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
