import SwiftUI

struct WritingPreferencesSheet: View {
    let initial: WritingPreferences
    let save: (WritingPreferences) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var design: WritingFontDesign
    @State private var scale: Double
    @State private var spacing: Double
    @State private var limited: Bool
    @State private var width: Double
    @State private var toolbar: [WritingToolbarItem]
    @State private var error: String?
    init(initial: WritingPreferences, save: @escaping (WritingPreferences) -> String?) {
        self.initial = initial; self.save = save
        _design = State(initialValue: initial.fontDesign); _scale = State(initialValue: initial.fontScale)
        _spacing = State(initialValue: initial.lineSpacing); _limited = State(initialValue: initial.contentWidth != nil)
        _width = State(initialValue: initial.contentWidth ?? 780); _toolbar = State(initialValue: initial.toolbar)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Schrift und Lesbarkeit") {
                    Text("Diese Einstellungen gelten für alle Seiten im aktuellen Space dieser Bibliothek.").font(.caption)
                    Picker("Textschrift", selection: $design) {
                        Text("System").tag(WritingFontDesign.system)
                        Text("Serifen").tag(WritingFontDesign.serif)
                        Text("Gerundet").tag(WritingFontDesign.rounded)
                        Text("Monospace").tag(WritingFontDesign.monospaced)
                    }
                    LabeledContent("Schriftgröße", value: scale.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $scale, in: 0.8...1.6, step: 0.05).accessibilityLabel("Schriftgröße")
                    LabeledContent("Zusätzlicher Zeilenabstand", value: spacing.formatted())
                    Slider(value: $spacing, in: 0...20, step: 1).accessibilityLabel("Zeilenabstand")
                    Toggle("Textbreite begrenzen", isOn: $limited)
                    if limited {
                        LabeledContent("Maximale Textbreite", value: width.formatted())
                        Slider(value: $width, in: 320...1200, step: 20).accessibilityLabel("Textbreite")
                    }
                    Text("Die System-Schriftgröße bleibt wirksam. Quelltext, Code und Tabellen verwenden weiterhin Monospace.").font(.caption)
                }
                Section("Werkzeugleiste") {
                    ForEach(toolbar, id: \.command) { item in
                        WritingToolbarPreferenceRow(item: item, toggle: { value in
                            if let index = toolbar.firstIndex(where: { $0.command == item.command }) {
                                toolbar[index] = WritingToolbarItem(command: item.command, isVisible: value)
                            }
                        }, move: { delta in
                            guard let index = toolbar.firstIndex(where: { $0.command == item.command }), toolbar.indices.contains(index + delta) else { return }
                            toolbar.swapAt(index, index + delta)
                        })
                    }
                }
                if let error { Text(error).foregroundStyle(Color.primary) }
                Button("Standard wiederherstellen") {
                    let value = WritingPreferences.standard
                    design = value.fontDesign; scale = value.fontScale; spacing = value.lineSpacing
                    limited = value.contentWidth != nil; width = value.contentWidth ?? 780; toolbar = value.toolbar
                }
            }.navigationTitle("Editor-Einstellungen")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            do {
                                let value = try WritingPreferences(fontDesign: design, fontScale: scale, lineSpacing: spacing, contentWidth: limited ? width : nil, toolbar: toolbar)
                                if let failure = save(value) { error = failure } else { dismiss() }
                            } catch { self.error = "Die Einstellungen konnten nicht gespeichert werden." }
                        }
                    }
                }
        }.interactiveDismissDisabled(initial != candidate)
    }
    private var candidate: WritingPreferences? { try? WritingPreferences(fontDesign: design, fontScale: scale, lineSpacing: spacing, contentWidth: limited ? width : nil, toolbar: toolbar) }
}

private struct WritingToolbarPreferenceRow: View {
    let item: WritingToolbarItem
    let toggle: (Bool) -> Void
    let move: (Int) -> Void
    var body: some View {
        HStack {
            Toggle(item.command.title, isOn: Binding(get: { item.isVisible }, set: toggle))
            Button { move(-1) } label: {
                Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.accessibilityLabel("Nach oben")
            Button { move(1) } label: {
                Image(systemName: "arrow.down").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.accessibilityLabel("Nach unten")
        }.buttonStyle(.borderless)
    }
}
extension WritingToolbarCommand {
    var title: LocalizedStringKey { switch self { case .heading: "Überschrift"; case .bold: "Fett"; case .italic: "Kursiv"; case .list: "Liste" } }
    var symbol: String { switch self { case .heading: "textformat.size"; case .bold: "bold"; case .italic: "italic"; case .list: "list.bullet" } }
    var prefix: String { switch self { case .heading: "## "; case .bold: "**"; case .italic: "*"; case .list: "- " } }
    var suffix: String { switch self { case .heading, .list: ""; case .bold: "**"; case .italic: "*" } }
}
