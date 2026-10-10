import Foundation
import ImageIO
import CoreGraphics
import Testing
@testable import SkriptumExport

func orientedPhoto(_ orientation: Int) throws -> ExportAsset {
    let width = 80, height = 40
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    let colors: [[UInt8]] = [[240,20,20], [20,220,20], [20,20,240], [240,220,20]]
    for y in 0..<height { for x in 0..<width {
        let color = colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
        let index = (y * width + x) * 4
        for c in 0..<3 { pixels[index+c] = color[c] }
    } }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return ExportAsset(data: data as Data, mediaType: "image/jpeg")
}

private func corners(_ data: Data) throws -> (Int, Int, [Int]) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let width = image.width, height = image.height
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let buffer = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let palette = [[240,20,20], [20,220,20], [20,20,240], [240,220,20]]
    let labels = [(width/4,height/4),(3*width/4,height/4),(width/4,3*height/4),(3*width/4,3*height/4)].map { x,y in
        let i = (y*width+x)*4
        return palette.indices.min { a,b in
            (0..<3).reduce(0) { $0 + abs(Int(buffer[i+$1])-palette[a][$1]) }
            < (0..<3).reduce(0) { $0 + abs(Int(buffer[i+$1])-palette[b][$1]) }
        }!
    }
    return (width,height,labels)
}

@Test func wordExportNormalizesEveryEXIFOrientationWithoutShrinkingOrMutatingInput() throws {
    let expected = [[0,1,2,3],[1,0,3,2],[3,2,1,0],[2,3,0,1],[0,2,1,3],[2,0,3,1],[3,1,2,0],[1,3,0,2]]
    for orientation in 1...8 {
        let original = try orientedPhoto(orientation), before = original.data
        let result = try DOCXImageOrientation.normalized(original, path: "photo.jpg")
        let (width,height,labels) = try corners(result.data)
        #expect(width == (orientation >= 5 ? 40 : 80))
        #expect(height == (orientation >= 5 ? 80 : 40))
        #expect(labels == expected[orientation-1], "Orientation \(orientation)")
        #expect(original.data == before)
        if orientation == 1 { #expect(result.data == before); #expect(result.mediaType == "image/jpeg") }
        else { #expect(result.mediaType == "image/png") }
    }
}

@Test func orientedPhotoDOCXPackageUsesUprightPNGAndPortraitDrawingExtent() throws {
    #if os(macOS)
    let original = try orientedPhoto(6)
    let input = ExportInput(title: "Portrait", markdown: "![Portrait](photo.jpg)", assets: ["photo.jpg": original])
    let artifact = try ExportEngine.export(input, format: .docx)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("portrait.docx"); try artifact.data.write(to: file)
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", """
import zipfile,sys,xml.etree.ElementTree as E
with zipfile.ZipFile(sys.argv[1]) as z:
 assert z.testzip() is None
 assert 'word/media/image1.png' in z.namelist()
 assert 'word/media/image1.jpg' not in z.namelist()
 assert z.read('word/media/image1.png').startswith(b'\\x89PNG')
 n={'wp':'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing','r':'http://schemas.openxmlformats.org/package/2006/relationships'}
 d=E.fromstring(z.read('word/document.xml')); e=d.find('.//wp:extent',n)
 assert int(e.get('cy'))==2*int(e.get('cx'))
 assert int(e.get('cx'))==40*9525
 assert int(e.get('cy'))==80*9525
 rel=E.fromstring(z.read('word/_rels/document.xml.rels'))
 assert any(x.get('Target')=='media/image1.png' for x in rel)
""",file.path]
    try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    #expect(input.assets["photo.jpg"]?.data == original.data)
    #endif
}
