import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum WritingPreferencesStorageError: Error, Equatable { case invalidScope, invalidStoredData }

extension WritingLibrary {
    func writingPreferenceKey(spaceID: UUID) throws -> String {
        guard let store, store.snapshot.spaces.contains(where: { $0.id == spaceID }),
              let key = WritingPreferences.storageKey(libraryNamespace: try assistantHistoryDirectory().lastPathComponent, spaceID: spaceID) else {
            throw WritingPreferencesStorageError.invalidScope
        }
        return key
    }
    func loadWritingPreferences(spaceID: UUID) throws -> WritingPreferences {
        let key = try writingPreferenceKey(spaceID: spaceID)
        guard let object = preferences.object(forKey: key) else { return .standard }
        guard let data = object as? Data else { throw WritingPreferencesStorageError.invalidStoredData }
        return try JSONDecoder().decode(WritingPreferences.self, from: data)
    }
    func saveWritingPreferences(_ value: WritingPreferences, spaceID: UUID) throws {
        let key = try writingPreferenceKey(spaceID: spaceID)
        // Immutable model has passed the same constructor/decoder validation.
        preferences.set(try JSONEncoder().encode(value), forKey: key)
    }
}
