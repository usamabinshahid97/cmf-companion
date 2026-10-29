import BudsCore
import SwiftUI

struct ANCIntensitySelector: View {
    var selection: NoiseMode?
    var enabled: Bool
    var select: (NoiseMode) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accentText: Color { scheme == .dark ? CMFStyle.accentLight : CMFStyle.accentInk }

    var body: some View {
        HStack(spacing: 10) {
            Text("Intensity").font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            GlassCluster(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach([NoiseMode.low, .medium, .high, .adaptive]) { mode in
                        choice(mode)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ANC intensity")
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: selection)
    }

    private func choice(_ mode: NoiseMode) -> some View {
        let selected = selection == mode
        return Button {
            guard enabled, selection != mode else { return }
            select(mode)
        } label: {
            HStack(spacing: 3) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        .transition(.opacity)
                }
                Text(mode.title).font(.system(size: 10.5, weight: selected ? .semibold : .medium)).lineLimit(1)
            }
            .foregroundStyle(selected ? accentText : Color.primary.opacity(0.8))
            .frame(maxWidth: .infinity).frame(height: 32)
            .controlGlass(radius: 16,
                          tint: selected ? CMFStyle.accent.opacity(scheme == .dark ? 0.20 : 0.13) : nil,
                          interactive: enabled)
            .hoverHighlight(radius: 16)
            .contentShape(Capsule())
        }
        .buttonStyle(IntensityChoiceStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("\(mode.title) ANC intensity")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("Set noise cancellation intensity to \(mode.title.lowercased())")
    }
}

private struct IntensityChoiceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.76 : 1)
    }
}
