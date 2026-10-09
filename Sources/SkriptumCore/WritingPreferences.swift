import Foundation
public enum WritingFontDesign: String, Codable, CaseIterable, Sendable { case system, serif, rounded, monospaced }
public enum WritingToolbarCommand: String, Codable, CaseIterable, Sendable { case heading, bold, italic, list }
public struct WritingToolbarItem: Codable, Equatable, Sendable {
 public let command: WritingToolbarCommand
 public let isVisible: Bool
 public init(command: WritingToolbarCommand,isVisible: Bool) { self.command = command; self.isVisible = isVisible }
}
public enum WritingPreferencesError: Error, Equatable { case unsupportedSchema, invalidValue, invalidToolbar }
/// Presentation-only settings: no Markdown text, offsets, block IDs or provider settings.
public struct WritingPreferences: Codable, Equatable, Sendable {
 public let schemaVersion: Int
 public let fontDesign: WritingFontDesign
 public let fontScale: Double
 /// Extra spacing between lines, in points, above native font metrics.
 public let lineSpacing: Double
 /// Preferred maximum readable content width, in points. nil follows available width.
 public let contentWidth: Double?
 /// All supported commands exactly once; order and explicit visibility are independent.
 public let toolbar: [WritingToolbarItem]
 public var visibleCommands: [WritingToolbarCommand] { toolbar.filter(\.isVisible).map(\.command) }
 public static let standard = Self(standardDefaults: ())
 private init(standardDefaults: Void) {
  schemaVersion = 1; fontDesign = .system; fontScale = 1; lineSpacing = 0; contentWidth = 780; toolbar = Self.defaultToolbar
 }
 public static var defaultToolbar: [WritingToolbarItem] { WritingToolbarCommand.allCases.map { .init(command:$0,isVisible:true) } }
 public init(fontDesign:WritingFontDesign = .system,fontScale:Double = 1,lineSpacing:Double = 0,contentWidth:Double? = 780,toolbar:[WritingToolbarItem] = defaultToolbar) throws {
  guard fontScale.isFinite,(0.8...1.6).contains(fontScale),lineSpacing.isFinite,(0...20).contains(lineSpacing),contentWidth.map({ $0.isFinite && (320...1200).contains($0) }) ?? true else { throw WritingPreferencesError.invalidValue }
  guard toolbar.count == WritingToolbarCommand.allCases.count, Set(toolbar.map(\.command)) == Set(WritingToolbarCommand.allCases) else { throw WritingPreferencesError.invalidToolbar }
  schemaVersion = 1; self.fontDesign = fontDesign; self.fontScale = fontScale; self.lineSpacing = lineSpacing; self.contentWidth = contentWidth; self.toolbar = toolbar
 }
 private enum CodingKeys:String,CodingKey { case schemaVersion,fontDesign,fontScale,lineSpacing,contentWidth,toolbar }
 public init(from decoder:any Decoder) throws {
  let c = try decoder.container(keyedBy:CodingKeys.self)
  guard try c.decode(Int.self,forKey:.schemaVersion) == 1 else { throw WritingPreferencesError.unsupportedSchema }
  try self.init(fontDesign:c.decode(WritingFontDesign.self,forKey:.fontDesign),fontScale:c.decode(Double.self,forKey:.fontScale),lineSpacing:c.decode(Double.self,forKey:.lineSpacing),contentWidth:c.decodeIfPresent(Double.self,forKey:.contentWidth),toolbar:c.decode([WritingToolbarItem].self,forKey:.toolbar))
 }
 /// Namespace is supplied by the existing owning-library storage contract.
 /// Missing/unsafe scope has no global fallback and never writes preferences.
 public static func storageKey(libraryNamespace:String,spaceID:UUID) -> String? {
  guard !libraryNamespace.isEmpty,libraryNamespace.utf8.count <= 128,libraryNamespace.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
  return "Scriptum.writing." + libraryNamespace + "." + spaceID.uuidString
 }
}
