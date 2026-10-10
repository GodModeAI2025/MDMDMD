import SwiftUI
#if canImport(SkriptumCore)
import SkriptumCore
#endif

/// Read presentation retains every source character; selection/edit admission
/// continues to use the original block and reversible raw projection.
struct CompositeWritingText: View {
    let source: String
    let preferences: WritingPreferences
    @ScaledMetric private var bodySize = 17.0
    @ScaledMetric(relativeTo: .largeTitle) private var largeSize = 34.0
    @ScaledMetric(relativeTo: .title) private var titleSize = 28.0
    @ScaledMetric(relativeTo: .title3) private var headingSize = 20.0
    @State private var plan: MarkdownSourcePresentation?
    private var design: Font.Design {
        switch preferences.fontDesign { case .system: .default; case .serif: .serif; case .rounded: .rounded; case .monospaced: .monospaced }
    }
    var body: some View {
        Text(styled).font(.system(size: bodySize * preferences.fontScale, design: design))
            .task(id: Data(source.utf8)) {
                do {
                    let value = try await MarkdownPresentationWorker.shared.make(source)
                    try Task.checkCancellation()
                    plan = value
                } catch { /* Unchanged source remains available without styles. */ }
            }
    }
    private var styled: AttributedString {
        var value = AttributedString(source)
        guard let plan, plan.source.utf8.elementsEqual(source.utf8) else { return value }
        for run in plan.runs {
            guard let range = Range(run.range, in: source),
                  let start = AttributedString.Index(range.lowerBound, within: value),
                  let end = AttributedString.Index(range.upperBound, within: value) else { continue }
            switch run.style {
            case .heading(let level):
                let size = level <= 1 ? largeSize : level == 2 ? titleSize : headingSize
                value[start..<end].font = .system(size: size * preferences.fontScale, weight: .bold, design: design)
            case .code: value[start..<end].font = .system(size: bodySize * preferences.fontScale, design: .monospaced)
            case .strong:
                var intent = value[start..<end].inlinePresentationIntent ?? []
                intent.insert(.stronglyEmphasized); value[start..<end].inlinePresentationIntent = intent
            case .emphasis:
                var intent = value[start..<end].inlinePresentationIntent ?? []
                intent.insert(.emphasized); value[start..<end].inlinePresentationIntent = intent
            }
        }
        return value
    }
}
