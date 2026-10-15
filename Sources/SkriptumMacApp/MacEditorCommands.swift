import SwiftUI

/// Stable per-editor command target; the focused window owns all actions.
@MainActor @Observable final class MacEditorCommandContext {
    var perform: (@MainActor (MacEditorIntent) -> Void)?
    var editable = false
    var canUndoAI = false
    var canRedoAI = false
    func send(_ intent: MacEditorIntent) { perform?(intent) }
}
enum MacEditorIntent: Equatable {
    case bold, italic, heading, list, link, image, appearance, reference, links, attachments
    case assistant, proofread, rewrite, summarize, quality
    case writing, source, preview, inspector, export, undoAI, redoAI
}
extension FocusedValues { @Entry var macEditor: MacEditorCommandContext? }

enum MacWritingAppearance {
    static let defaults = (try? WritingPreferences(fontDesign: .serif, fontScale: 1, lineSpacing: 5, contentWidth: 700)) ?? .standard
}

struct MacEditorMenuCommands: Commands {
    @FocusedValue(\.macEditor) private var editor
    @FocusedValue(\.macWorkspace) private var workspace
    var body: some Commands {
        CommandMenu("Format") {
            Button("Fett") { editor?.send(.bold) }.keyboardShortcut("b").disabled(editor?.editable != true)
            Button("Kursiv") { editor?.send(.italic) }.keyboardShortcut("i").disabled(editor?.editable != true)
            Divider()
            Button("Überschrift") { editor?.send(.heading) }.disabled(editor?.editable != true)
            Button("Liste") { editor?.send(.list) }.disabled(editor?.editable != true)
            Button("Link einfügen …") { editor?.send(.link) }.disabled(editor?.editable != true)
            Button("Seitenverweis einfügen …") { editor?.send(.reference) }.disabled(editor?.editable != true)
            Button("Bild hinzufügen …") { editor?.send(.image) }.disabled(editor?.editable != true)
            Divider()
            Button("Schreibdarstellung …") { editor?.send(.appearance) }.disabled(editor == nil)
            Button("Textänderung rückgängig") { editor?.send(.undoAI) }.disabled(editor?.canUndoAI != true)
            Button("Textänderung wiederholen") { editor?.send(.redoAI) }.disabled(editor?.canRedoAI != true)
        }
        CommandMenu("Schreiben") {
            Button(workspace?.writingFocus == true ? "Schreibfokus beenden" : "Schreibfokus") { workspace?.toggleWritingFocus() }
                .keyboardShortcut("f", modifiers: [.command, .option]).disabled(workspace?.selectedPage == nil)
            Divider()
            Button("Schreibansicht") { editor?.send(.writing) }.disabled(editor == nil)
            Button("Markdown-Quelltext") { editor?.send(.source) }.disabled(editor == nil)
            Button("Vorschau") { editor?.send(.preview) }.disabled(editor == nil)
            Button("Seiteninfo und Kommentare") { editor?.send(.inspector) }.disabled(editor == nil)
            Button("Verweise und Rückverweise …") { editor?.send(.links) }.disabled(editor == nil)
            Button("Anhänge und Verwendung …") { editor?.send(.attachments) }.disabled(editor == nil)
            Divider()
            Button("KI-Assistent …") { editor?.send(.assistant) }.disabled(editor == nil)
            Button("Lektorat …") { editor?.send(.proofread) }.disabled(editor?.editable != true)
            Button("Überarbeiten …") { editor?.send(.rewrite) }.disabled(editor?.editable != true)
            Button("Zusammenfassen …") { editor?.send(.summarize) }.disabled(editor == nil)
            Button("Textprüfung …") { editor?.send(.quality) }.disabled(editor == nil)
            Divider()
            Button("Exportieren …") { editor?.send(.export) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(editor == nil)
        }
    }
}
