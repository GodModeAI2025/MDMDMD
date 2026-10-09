import SwiftUI

struct TemplatePickerSheet: View {
    let library: WritingLibrary
    let targetSpaceID: UUID?
    let prepare: () -> Bool
    let created: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [WritingPage] = []
    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty { Text("Markieren Sie eine Seite über Seitenaktionen → Seitenart als Vorlage. Inhalt, Bilder, Regeln und Prompts werden in neue Texte übernommen.").foregroundStyle(.secondary) }
                ForEach(templates) { template in
                    Button {
                        guard prepare(), let id = library.instantiateTemplate(template, spaceID: targetSpaceID) else { return }
                        created(id); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.title.isEmpty ? "Ohne Titel" : template.title)
                            Text("\(template.attachments?.count ?? 0) Bilder · \(template.reusablePrompts?.count ?? 0) Prompts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = library.saveError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Aus Vorlage erstellen")
            .toolbar { Button("Schließen") { dismiss() } }
            .onAppear { templates = library.pages.filter { !$0.trashed && $0.effectivePurpose == .template }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
        }
    }
}
