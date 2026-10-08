import Foundation

public enum ExportFont: String, Codable, CaseIterable, Equatable, Sendable {
    case georgia, timesNewRoman, palatino, helvetica, courierNew
    public var displayName: String {
        switch self { case .georgia: "Georgia"; case .timesNewRoman: "Times New Roman"; case .palatino: "Palatino"; case .helvetica: "Helvetica"; case .courierNew: "Courier New" }
    }
    var cssFamily: String { "'\(displayName)',\(self == .courierNew ? "monospace" : self == .helvetica ? "sans-serif" : "serif")" }
}
public enum ExportPaperSize: String, Codable, CaseIterable, Equatable, Sendable {
    case a4, letter
    public var widthMM: Double { self == .a4 ? 210 : 215.9 }
    public var heightMM: Double { self == .a4 ? 297 : 279.4 }
    var cssName: String { self == .a4 ? "A4" : "Letter" }
}

/// A portable, declarative style. No free-form CSS, fonts, paths or URLs are accepted.
/// Mutable UI drafts are revalidated at each export; persisted data is validated on decode.
public struct ExportTheme: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bodyFont: ExportFont
    public var bodySizePoints: Double
    public var lineHeight: Double
    public var paragraphSpacingPoints: Double
    public var marginsMM: Double
    public var paperSize: ExportPaperSize
    public var headingColorHex: String
    public var includeTitle: Bool
    public var includeTOC: Bool
    public init(id: String = "custom", name: String = "Custom", bodyFont: ExportFont = .georgia, bodySizePoints: Double = 12, lineHeight: Double = 1.65, paragraphSpacingPoints: Double = 8, marginsMM: Double = 25.4, paperSize: ExportPaperSize = .a4, headingColorHex: String = "17202A", includeTitle: Bool = false, includeTOC: Bool = false) throws {
        self.id = id; self.name = name; self.bodyFont = bodyFont; self.bodySizePoints = bodySizePoints; self.lineHeight = lineHeight; self.paragraphSpacingPoints = paragraphSpacingPoints; self.marginsMM = marginsMM; self.paperSize = paperSize; self.headingColorHex = headingColorHex.hasPrefix("#") ? String(headingColorHex.dropFirst()) : headingColorHex; self.includeTitle = includeTitle; self.includeTOC = includeTOC
        try validate()
    }
    public func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 64, id.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "-" || $0 == "_" }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 160,
              name.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
              bodySizePoints.isFinite, (8...36).contains(bodySizePoints),
              lineHeight.isFinite, (1...3).contains(lineHeight),
              paragraphSpacingPoints.isFinite, (0...48).contains(paragraphSpacingPoints),
              marginsMM.isFinite, (5...50).contains(marginsMM),
              headingColorHex.utf8.count == 6, headingColorHex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw ExportError.invalidMetadata("export theme") }
    }
    private enum CodingKeys: String, CodingKey { case id, name, bodyFont, bodySizePoints, lineHeight, paragraphSpacingPoints, marginsMM, paperSize, headingColorHex, includeTitle, includeTOC }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(String.self, forKey: .id), name: c.decode(String.self, forKey: .name), bodyFont: c.decode(ExportFont.self, forKey: .bodyFont), bodySizePoints: c.decode(Double.self, forKey: .bodySizePoints), lineHeight: c.decode(Double.self, forKey: .lineHeight), paragraphSpacingPoints: c.decode(Double.self, forKey: .paragraphSpacingPoints), marginsMM: c.decode(Double.self, forKey: .marginsMM), paperSize: c.decode(ExportPaperSize.self, forKey: .paperSize), headingColorHex: c.decode(String.self, forKey: .headingColorHex), includeTitle: c.decode(Bool.self, forKey: .includeTitle), includeTOC: c.decode(Bool.self, forKey: .includeTOC))
    }
    // Literal presets use the same public validator; a failed constant is a programmer error.
    public static let standard = try! ExportTheme(id: "standard", name: "Standard")
    public static let manuscript = try! ExportTheme(id: "manuscript", name: "Manuscript", bodyFont: .courierNew, lineHeight: 2)
    public static let ebook = try! ExportTheme(id: "ebook", name: "E-Book")
    public static var presets: [ExportTheme] { [.standard, .manuscript, .ebook] }
    public static func preset(for profile: ExportProfile) -> ExportTheme {
        switch profile { case .standard: .standard; case .manuscript: .manuscript; case .ebook: .ebook }
    }
}

func cssNumber(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(value)
}
func themeCSS(_ theme: ExportTheme) -> String {
    "@page{size:\(theme.paperSize.cssName);margin:\(cssNumber(theme.marginsMM))mm}" +
    "body{font-family:\(theme.bodyFont.cssFamily);font-size:\(cssNumber(theme.bodySizePoints))pt;line-height:\(cssNumber(theme.lineHeight));max-width:42rem;margin:2rem auto;padding:0 1.2rem;color:#17202a;background:#fff}" +
    "h1,h2,h3,h4,h5,h6{color:#\(theme.headingColorHex);line-height:1.25;break-after:avoid-page;page-break-after:avoid;page-break-inside:avoid}" +
    "p{margin:0 0 \(cssNumber(theme.paragraphSpacingPoints))pt;widows:3;orphans:3}tr{break-inside:avoid;page-break-inside:avoid}pre{white-space:pre-wrap;background:#f3f4f5;padding:1rem}code{font-family:monospace}blockquote{border-left:3px solid #889;padding-left:1rem;margin-left:0}table{border-collapse:collapse;width:100%}th,td{border:1px solid #aaa;padding:.4rem;text-align:left}img{max-width:100%;height:auto}aside{font-size:.9em}a{color:#164d88}nav[aria-label='Contents']{margin:1em 0}@media print{body{max-width:none;margin:0;padding:0}}"
}
