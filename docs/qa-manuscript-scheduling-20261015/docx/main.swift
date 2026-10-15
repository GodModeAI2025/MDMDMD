import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import AppKit
import SkriptumExport

@main struct Audit {
 static func main() async throws {
  let root = URL(fileURLWithPath: "/private/tmp/scriptum-export-profile-audit")
  let ctx = CGContext(data: nil, width: 2400, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(CGColor(red: 0.15, green: 0.3, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 2400, height: 800))
  let image = ctx.makeImage()!; let data = NSMutableData(); let dst = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(dst, image, nil); precondition(CGImageDestinationFinalize(dst))
  let theme = try ExportTheme(bodySizePoints: 12, marginsMM: 25.4, paperSize: .a4)
  let source = "| Figure | Notes |\n| --- | --- |\n| ![Wide figure](wide.png) | This text should stay within the right-hand cell. |\n\n> ![Quoted figure](wide.png)\n\n- ![Listed figure](wide.png)"
  let input = ExportInput(title: "Image sizing", markdown: source, assets: ["wide.png": ExportAsset(data: data as Data, mediaType: "image/png")], theme: theme)
  for format in [ExportFormat.docx, .html, .epub] { try ExportEngine.export(input, format: format).data.write(to: root.appendingPathComponent("page." + format.rawValue)) }
  let pdf = try await ExportEngine.renderSemanticPDF(input); try pdf.data.write(to: root.appendingPathComponent("page.pdf"))
  try Data(source.utf8).write(to: root.appendingPathComponent("source.md"))
  print("Exported actual current artifacts at \(root.path)")
 }
}
