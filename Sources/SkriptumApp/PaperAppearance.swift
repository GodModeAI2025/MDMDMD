import SwiftUI

/// Static, decorative paper; no timeline, state, network or random rendering.
struct PaperSurface: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color("PaperBase"), Color("PaperEdge")], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                for index in 0..<640 {
                    let x = Double((index * 137 + 23) % 997) / 997 * size.width
                    let y = Double((index * 281 + 47) % 991) / 991 * size.height
                    let radius = index % 3 == 0 ? 0.65 : 0.35
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)), with: .color(Color("PaperShadow")))
                }
            }.opacity(contrast == .increased ? 0 : (scheme == .dark ? 0.12 : 0.09))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PressedScriptumWordmark: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var mask: some View { Image("ScriptumWordmark").renderingMode(.template).resizable().scaledToFit() }
    var body: some View {
        ZStack {
            mask.foregroundStyle(Color("PaperHighlight")).offset(x: 0.7, y: 1.1).opacity(contrast == .increased ? 0 : 0.85)
            mask.foregroundStyle(Color("PaperShadow")).offset(x: -0.4, y: -0.7).opacity(contrast == .increased ? 0 : 0.55)
            mask.foregroundStyle(Color("PaperInk")).opacity(contrast == .increased ? 1 : 0.82)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Scriptum")
    }
}

struct ScriptumPaperBrand: View {
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var compactAccessibility: Bool { compact && dynamicTypeSize.isAccessibilitySize }
    var body: some View {
        VStack(spacing: compact ? 4 : 10) {
            PressedScriptumWordmark().frame(height: compactAccessibility ? 26 : (compact ? 54 : 112))
            Text("Ohne Hast, aber ohne Rast.")
                .font(.system(compact ? .caption : .callout, design: .serif)).foregroundStyle(Color.primary)
            Text(compactAccessibility ? LocalizedStringKey("— Goethe") : LocalizedStringKey("— Johann Wolfgang von Goethe"))
                .font(compact ? .caption2 : .caption).foregroundStyle(Color.secondary)
                .accessibilityLabel("Johann Wolfgang von Goethe")
        }.multilineTextAlignment(.center)
    }
}


/// Reads the window's Dynamic Type environment nearest to the accessory consumer.
struct ScriptumLaunchBrand: View {
    let frame: CGRect
    let titleFrame: CGRect
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let compact = frame.width < 600
        let offset: CGFloat = compact ? (dynamicTypeSize.isAccessibilitySize ? 20 : 40) : 110
        ScriptumPaperBrand(compact: compact)
            .frame(width: min(max(frame.width - 40, 160), 500))
            .position(x: frame.midX, y: titleFrame.minY + offset)
            .allowsHitTesting(false)
    }
}
