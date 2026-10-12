import Foundation
@testable import SkriptumBlocks
var frame = BlockInputFrame(source: "Text\n\n")
let typed = "# Foo"
let source = frame.proposedSource(text: typed, canonical: frame.source)!
frame.accept(text: typed, source: source)
let body = NSRange(location: 2, length: 3)
let displayed = (frame.text as NSString).substring(with: body)
let correct = frame.sourceSelection(body, text: frame.text)
let canonical = BlockProjection(frame.source)
let start = canonical.sourceOffset(for: body.location)
let end = canonical.sourceOffset(for: body.location + body.length)
let wrong = NSRange(location: start, length: max(0, end - start))
print(String(data: try JSONSerialization.data(withJSONObject: ["nativeText": frame.text, "canonicalSource": frame.source, "displayedSelection": displayed, "sourceSelection": [correct.location, correct.length], "canonicalReprojection": [wrong.location, wrong.length], "wrongSelectedSource": (frame.source as NSString).substring(with: wrong)], options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
