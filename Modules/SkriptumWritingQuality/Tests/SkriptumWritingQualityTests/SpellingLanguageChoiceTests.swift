import Testing
@testable import SkriptumWritingQuality

@Test func unsupportedDetectedSpellingLanguageDoesNotAdoptFirstOrSystemDictionary() {
    #expect(SpellingLanguageChoice.suggested(detected: "fa", system: "de_DE", dictionaries: ["ar", "de_DE", "en_US"]) == nil)
    #expect(SpellingLanguageChoice.suggested(detected: "", system: "de_DE", dictionaries: ["de_DE"]) == nil)
}
@Test func nativeSpellingChoicePreservesScriptAndPrefersMatchingLocale() {
    #expect(SpellingLanguageChoice.suggested(detected: "zh-Hans", system: "en_US", dictionaries: ["zh_Hant", "zh_Hans"]) == "zh_Hans")
    #expect(SpellingLanguageChoice.suggested(detected: "zh-Hans", system: "zh_Hant", dictionaries: ["zh_Hant"]) == nil)
    #expect(SpellingLanguageChoice.suggested(detected: "en", system: "en_GB", dictionaries: ["en_US", "en_GB"]) == "en_GB")
    #expect(SpellingLanguageChoice.suggested(detected: "en", system: "en_GB", dictionaries: ["en", "en_GB"]) == "en_GB")
    #expect(SpellingLanguageChoice.suggested(detected: "en_US", system: "en_GB", dictionaries: ["en_US", "en_GB"]) == "en_US")
    #expect(SpellingLanguageChoice.suggested(detected: nil, system: "de_DE", dictionaries: ["ar", "de_DE"]) == "de_DE")
}
