import Foundation
import ImageIO
import CoreGraphics
import SkriptumExport
func require<T>(_ value: T?) throws -> T { guard let value else { throw CocoaError(.fileReadCorruptFile) }; return value }
private func orientedPhoto(_ orientation: Int) throws -> ExportAsset {
    let width = 80, height = 40
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    let colors: [[UInt8]] = [[240,20,20], [20,220,20], [20,20,240], [240,220,20]]
    for y in 0..<height { for x in 0..<width {
        let color = colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
        let index = (y * width + x) * 4
        for c in 0..<3 { pixels[index+c] = color[c] }
    } }
    let provider = try require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return ExportAsset(data: data as Data, mediaType: "image/jpeg")
}


let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for orientation in [6, 2] {
    let photo = try orientedPhoto(orientation)
    let input = ExportInput(title: "Scriptum Word Bildprüfung", markdown: "# Bildausrichtung \(orientation)\n\nVier farbige Ecken prüfen die Ausrichtung.\n\n![Vier farbige Ecken](photo.jpg)\n\nEnde der Bildprüfung.", assets: ["photo.jpg": photo])
    let artifact = try ExportEngine.export(input, format: .docx)
    try artifact.data.write(to: folder.appendingPathComponent("Scriptum-Word-Orientierung-\(orientation).docx"))
    try photo.data.write(to: folder.appendingPathComponent("Original-\(orientation).jpg"))
}
