import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import SkriptumExport

@Test(arguments: [ExportPaperSize.a4, .letter])
func docxImagesRespectParagraphAndTableContentWidths(paper: ExportPaperSize) throws {
    #if os(macOS)
    let wide = try docxLayoutImage(width: 2400, height: 800)
    let small = try docxLayoutImage(width: 40, height: 20)
    let source = """
    ![plain](wide.png)

    > ![quote](wide.png)
    >
    > > ![nestedQuote](wide.png)

    ---

    - ![list](wide.png)

      ![continuedList](wide.png)

      - ![nestedList](wide.png)

    ---

    > - ![quoteList](wide.png)

    ---

    - > ![listQuote](wide.png)

    ---

    | Figure | Notes |
    | --- | --- |
    | ![table](wide.png) | Right-hand cell text. |

    > | Figure | Notes |
    > | --- | --- |
    > | ![quoteTable](wide.png) | Quoted table notes. |

    - Item

      | Figure | Notes |
      | --- | --- |
      | ![listTable](wide.png) | Listed table notes. |

    ---

    > **[![linked](wide.png)](https://example.com/figure)**
    >
    > ![small](small.png)

    Note[^n].

    [^n]: > ![footnoteQuote](wide.png)
    """
    let theme = try ExportTheme(marginsMM: paper == .a4 ? 25.4 : 45, paperSize: paper)
    let input = ExportInput(title: "Image layout", markdown: source,
        assets: ["wide.png": wide, "small.png": small], theme: theme)
    let artifact = try ExportEngine.export(input, format: .docx)
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("page.docx")
    try artifact.data.write(to: path)
    let check = """
import sys, zipfile, xml.etree.ElementTree as E
n={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main', 'wp':'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'}
w='{'+n['w']+'}'
with zipfile.ZipFile(sys.argv[1]) as z:
 d=E.fromstring(z.read('word/document.xml')); notes=E.fromstring(z.read('word/footnotes.xml'))
 size=d.find('.//w:pgSz',n); margin=d.find('.//w:pgMar',n)
 page=int(size.get(w+'w'))-int(margin.get(w+'left'))-int(margin.get(w+'right'))
 expected={'plain':0,'quote':720,'nestedQuote':1440,'list':720,'continuedList':720,'nestedList':1440,'quoteList':1440,'listQuote':1440,'linked':720,'small':720,'footnoteQuote':720}
 seen=set()
 for root in [d,notes]:
  parents={child:parent for parent in root.iter() for child in parent}
  for p in root.findall('.//w:p',n):
   image=p.find('.//wp:docPr',n)
   if image is None: continue
   name=image.get('descr'); extent=p.find('.//wp:extent',n)
   width=int(extent.get('cx')); height=int(extent.get('cy')); seen.add(name)
   inline=p.find('.//wp:inline',n)
   assert all(inline.get(key)=='0' for key in ['distT','distB','distL','distR']), (name,'implicit image distances')
   if name in expected:
    left=expected[name]; ind=p.find('w:pPr/w:ind',n)
    actual=int(ind.get(w+'left','0')) if ind is not None else 0
    assert actual==left, (name,'paragraph indent',actual,left)
    limit=(page-left)*635
   else:
    table=parents[parents[parents[p]]]
    # p -> tc -> tr -> tbl; fixed geometry must match actual cell widths.
    assert table.tag==w+'tbl'
    left=720 if name in ['quoteTable','listTable'] else 0
    props=table.find('w:tblPr',n)
    assert props.find('w:tblLayout',n).get(w+'type')=='fixed', name
    assert int(props.find('w:tblW',n).get(w+'w'))==page-left, name
    assert int(props.find('w:tblInd',n).get(w+'w'))==left, name
    widths=[int(c.get(w+'w')) for c in table.findall('w:tblGrid/w:gridCol',n)]
    assert len(widths)==2 and sum(widths)==page-left, (name,widths)
    for row in table.findall('w:tr',n):
     assert [int(c.find('w:tcPr/w:tcW',n).get(w+'w')) for c in row.findall('w:tc',n)]==widths, name
    cm=props.find('w:tblCellMar',n)
    padding=int(cm.find('w:left',n).get(w+'w'))+int(cm.find('w:right',n).get(w+'w'))
    limit=(widths[0]-padding)*635
   assert 0 < width <= limit, (name,'image exceeds content width',width,limit)
   ratio=2 if name=='small' else 3
   assert abs(width-height*ratio)<=3, (name,'aspect ratio changed')
   if name=='small': assert (width,height)==(381000,190500), ('small image enlarged',width,height)
 assert seen==set(expected)|{'table','quoteTable','listTable'}, seen
 assert b'Right-hand cell text.' in z.read('word/document.xml')
 assert b'https://example.com/figure' in z.read('word/_rels/document.xml.rels')
 assert len([name for name in z.namelist() if name.startswith('word/media/')])==2
 print('DOCX images fit actual indented paragraphs and table cells; natural size, aspect, notes and links retained')
"""
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", check, path.path]
    let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)))
    #expect(input.markdown == source && input.assets["wide.png"]?.data == wide.data && input.assets["small.png"]?.data == small.data)
    #endif
}

private func docxLayoutImage(width: Int, height: Int) throws -> ExportAsset {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.15, green: 0.3, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage()), data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return ExportAsset(data: data as Data, mediaType: "image/png")
}
