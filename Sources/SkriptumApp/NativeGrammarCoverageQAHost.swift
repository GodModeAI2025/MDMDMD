#if DEBUG
import SwiftUI
import UIKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumWritingQuality)
import SkriptumWritingQuality
#endif

/// Synthetic source corpus only. No manuscripts, credentials, LanguageTool
/// requests or AI-provider calls. Zero findings never establish unavailability.
struct NativeGrammarCoverageQAHost: View {
    private struct Sample: Sendable { let language: String; let text: String }
    private struct Result: Codable, Sendable, Identifiable {
        var id: String { language }
        let language: String, spellingDictionary: String?, state: String
        let grammarFindings: Int, correctionFindings: Int
    }
    private static let samples: [Sample] = [
        .init(language: "en", text: "The unicode standard defines almost 150,000 characters."),
        .init(language: "de", text: "Das ist zwingendermaßen nicht erforderlich."),
        .init(language: "fr", text: "Il faut que grand carre soit à gauche."),
        .init(language: "es", text: "LA semana pasada no vino."),
        .init(language: "pt", text: "A traves de várias entrevistas..."),
        .init(language: "it", text: "Per dimostrare ch'è impossibile."),
        .init(language: "nl", text: "Ik heb het fiets op slot gezet."),
        .init(language: "sv", text: "Det visade sig efterhand att orden borde särskrivas."),
        .init(language: "da", text: "Nu har jeg jeg aldrig hørt magen."),
        .init(language: "pl", text: "Kupiłem wino chciałem też pić wodę."),
        .init(language: "ru", text: "Это случилось 31 ноября 2014 г."),
        .init(language: "el", text: "Είχα πάω."),
        .init(language: "ro", text: "La nu proiect."),
        .init(language: "sk", text: "Pri príležitosti medzinárodného dňa detí."),
        .init(language: "sl", text: "0 oseb ni manjkalo"),
        .init(language: "ar", text: "هذا السلامة"),
        .init(language: "zh", text: "我们应该削减不必要的开消。"),
        .init(language: "ja", text: "したがって。"),
        .init(language: "ast", text: "Foi a el cine cola so hermana."),
        .init(language: "be", text: "жанчына-урач"),
        .init(language: "br", text: "Ur karr nevez am eus prenet."),
        .init(language: "ca", text: "Per causalitat em vaig trobar el teu cosí al tren."),
        .init(language: "eo", text: "Mi lernas Esperanton ek de la jaro 2005."),
        .init(language: "fa", text: "ڪادو"),
        .init(language: "ga", text: "scoláire agus stáraí"),
        .init(language: "gl", text: "“Bo día, Frank,”dixo Hal."),
        .init(language: "km", text: "នោះ​ហើយ​នឹង​នេះ។"),
        .init(language: "ta", text: "புது மா கோலம் போடு மயிலே."),
        .init(language: "tl", text: "Baka ang tingin mo ay talo ka din."),
    ]
    @State private var results: [Result] = []
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var output = ""
    @State private var status = "Noch nicht gestartet"
    private struct LanguageReview: Identifiable {
        let id = UUID()
        let library: WritingLibrary
        let page: WritingPage
    }
    @State private var languageReview: LanguageReview?
    var body: some View {
        NavigationStack {
            List {
                Text("Nur synthetische Regelbeispiele. Rechtschreibwörterbücher belegen keine Grammatiksprachen. Null Treffer sind keine Abdeckungsaussage.")
                Button("Native Prüfung starten", action: start).disabled(running)
                Button("Rechtschreibsprachauswahl prüfen", action: showLanguageReview).disabled(running)
                if running { Button("Stoppen") { task?.cancel() } }
                Text(status).textSelection(.enabled)
                Text(output).textSelection(.enabled)
                ForEach(results) { result in
                    Text("\(result.language): Grammatik \(result.grammarFindings), Korrektur \(result.correctionFindings) · \(result.state)")
                }
            }.navigationTitle("Native Grammatikprüfung")
                .sheet(item: $languageReview) { item in
                    WritingQualitySheet(page: item.page, library: item.library, updated: { _ in }, aiAction: { _ in })
                }
        }
    }
    private func showLanguageReview() {
        do {
            let id = UUID().uuidString
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumSpellingChoiceUIQA-" + id)
            let documents = root.appendingPathComponent("Documents")
            let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
            let space = try store.createSpace(title: "Sprachauswahl")
            _ = try store.createPage(spaceID: space.id, title: "Persischer Prüftext", markdown: "این یک متن فارسی برای بررسی انتخاب زبان در ویرایشگر است. در این نوشته دربارهٔ کتاب، پژوهش و نگارش صحبت می‌کنیم. نویسنده می‌خواهد متن خود را با دقت بازبینی کند.")
            guard let preferences = UserDefaults(suiteName: "Scriptum.SpellingChoiceQA." + id) else { return }
            let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
            guard let page = library.pages.first else { return }
            languageReview = LanguageReview(library: library, page: page)
        } catch { status = error.localizedDescription }
    }
    private func start() {
        guard !running else { return }
        running = true; results = []; status = "Prüfung läuft"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumNativeGrammarCoverage-" + UUID().uuidString + ".json")
        output = file.path
        task = Task { @MainActor in
            defer { running = false; task = nil }
            let dictionaries = NativeWritingReviewer.spellingLanguages
            var consecutiveTimeouts = 0
            for sample in Self.samples {
                if Task.isCancelled { status = "Abgebrochen"; break }
                let dictionary = dictionaries.first { $0.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) == sample.language }
                var result: Result
                do {
                    let findings = try await NativeWritingReviewer.check(QualityDocument(source: sample.text, revision: UUID()), spellingLanguage: dictionary)
                    result = Result(language: sample.language, spellingDictionary: dictionary, state: "completed", grammarFindings: findings.filter { $0.ruleID == "APPLE_GRAMMAR" }.count, correctionFindings: findings.filter { $0.ruleID == "APPLE_CORRECTION" }.count)
                    consecutiveTimeouts = 0
                } catch {
                    if Task.isCancelled { status = "Abgebrochen"; break }
                    result = Result(language: sample.language, spellingDictionary: dictionary, state: String(describing: error), grammarFindings: 0, correctionFindings: 0)
                    if case QualityError.nativeGrammarTimeout = error { consecutiveTimeouts += 1 } else { consecutiveTimeouts = 0 }
                }
                results.append(result)
                do { try JSONEncoder().encode(results).write(to: file, options: .atomic) }
                catch { status = "Prüfprotokoll konnte nicht gespeichert werden"; break }
                status = "\(results.count) von \(Self.samples.count) · Sprachen mit Grammatikhinweisen: \(results.filter { $0.grammarFindings > 0 }.count)"
                if consecutiveTimeouts >= 3 { status += " · Nach drei aufeinanderfolgenden Zeitüberschreitungen gestoppt"; break }
            }
            if results.count == Self.samples.count { status += " · abgeschlossen" }
        }
    }
}
#endif
