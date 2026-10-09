import Foundation
import Testing
@testable import SkriptumCore
struct WritingPreferencesTests {
 @Test func validatedRoundTripAndOrdering() throws {
  let order: [WritingToolbarItem] = [.init(command:.list,isVisible:true),.init(command:.bold,isVisible:false),.init(command:.heading,isVisible:true),.init(command:.italic,isVisible:true)]
  let preferences = try WritingPreferences(fontDesign:.serif,fontScale:1.2,lineSpacing:8,contentWidth:700,toolbar:order)
  let decoded = try JSONDecoder().decode(WritingPreferences.self,from:JSONEncoder().encode(preferences))
  #expect(decoded == preferences)
  #expect(decoded.visibleCommands == [.list,.heading,.italic])
  #expect(try WritingPreferences().visibleCommands == [.heading,.bold,.italic,.list])
  #expect(try WritingPreferences() == .standard)
  #expect(WritingPreferences.standard.contentWidth == 780)
  let fullWidth = try WritingPreferences(contentWidth: nil)
  #expect(try JSONDecoder().decode(WritingPreferences.self, from: JSONEncoder().encode(fullWidth)).contentWidth == nil)
 }
 @Test func invalidInitializerAndStoredSettingsRejected() throws {
  #expect(throws:WritingPreferencesError.invalidValue) { try WritingPreferences(fontScale:.nan) }
  #expect(throws:WritingPreferencesError.invalidValue) { try WritingPreferences(lineSpacing:-1) }
  #expect(throws:WritingPreferencesError.invalidValue) { try WritingPreferences(contentWidth:20) }
  #expect(throws:WritingPreferencesError.invalidToolbar) { try WritingPreferences(toolbar:[.init(command:.bold,isVisible:true),.init(command:.bold,isVisible:false)]) }
  let bad = Data(#"{"schemaVersion":1,"fontDesign":"serif","fontScale":99,"lineSpacing":8,"contentWidth":700,"toolbar":[]}"#.utf8)
  #expect(throws:(any Error).self) { try JSONDecoder().decode(WritingPreferences.self,from:bad) }
  let future = Data(#"{"schemaVersion":2,"fontDesign":"serif","fontScale":1,"lineSpacing":8,"contentWidth":700,"toolbar":[]}"#.utf8)
  #expect(throws:WritingPreferencesError.unsupportedSchema) { try JSONDecoder().decode(WritingPreferences.self,from:future) }
 }
 @Test func scopeKeysAreSeparateAndUnavailableScopeHasNoFallback() {
  let space = UUID(), other = UUID()
  #expect(WritingPreferences.storageKey(libraryNamespace:"Chats",spaceID:space) != WritingPreferences.storageKey(libraryNamespace:"Chats",spaceID:other))
  #expect(WritingPreferences.storageKey(libraryNamespace:"Chats",spaceID:space) != WritingPreferences.storageKey(libraryNamespace:String(repeating:"a",count:64),spaceID:space))
  #expect(WritingPreferences.storageKey(libraryNamespace:"../Chats",spaceID:space) == nil)
  #expect(WritingPreferences.storageKey(libraryNamespace:"",spaceID:space) == nil)
 }
}
