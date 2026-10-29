import AppKit
import SwiftUI

enum CompanionLayout {
    static let width: CGFloat = 420
    static let height: CGFloat = 740
    static let inset: CGFloat = 20
}

enum CMFStyle {
    static let accent = Color(red: 0.97, green: 0.31, blue: 0.12)
    static let accentInk = Color(red: 0.74, green: 0.19, blue: 0.04)
    static let accentLight = Color(red: 1, green: 0.57, blue: 0.36)
    static let green = Color(red: 0.20, green: 0.68, blue: 0.43)
    static let hairline = Color.primary.opacity(0.075)
    static let body = Font.system(size: 13, weight: .medium)
    static let detail = Font.system(size: 11)
}

private struct LayoutSnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isLayoutSnapshot: Bool {
        get { self[LayoutSnapshotKey.self] }
        set { self[LayoutSnapshotKey.self] = newValue }
    }
}

enum CompanionAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// A child hosting controller has no SwiftUI presentation owner to receive its
/// preferredColorScheme. Keep the native popover's appearance in step with the
/// explicit SwiftUI scheme, without changing NSApplication or the system theme.
struct CompanionAppearanceBridge: NSViewRepresentable {
    var scheme: ColorScheme
    func makeNSView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.scheme = scheme
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: AppearanceView, context: Context) {
        view.scheme = scheme
        view.applyAppearance()
    }

    final class AppearanceView: NSView {
        var scheme: ColorScheme = .light
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }
        func applyAppearance() {
            guard let window else { return }
            let name: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
            if window.appearance?.name != name { window.appearance = NSAppearance(named: name) }
        }
    }
}

/// Read the app's system appearance independently of a popover's local override.
/// Removing a preferred scheme from an existing AppKit popover can otherwise retain it.
final class SystemAppearance: ObservableObject {
    static let shared = SystemAppearance()
    @Published private(set) var scheme: ColorScheme = .light
    private var observation: NSKeyValueObservation?
    private init() {
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] app, _ in
            let value: ColorScheme = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            if Thread.isMainThread { self?.scheme = value }
            else { DispatchQueue.main.async { self?.scheme = value } }
        }
    }
}

/// Ordinary system material forms the content layer; actual Liquid Glass is used on controls.
struct CompanionBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
            RadialGradient(colors: [CMFStyle.accent.opacity(scheme == .dark ? 0.17 : 0.13), .clear],
                           center: UnitPoint(x: 0.87, y: 0.13), startRadius: 2, endRadius: 240)
            RadialGradient(colors: [Color(red: 0.43, green: 0.53, blue: 0.68).opacity(scheme == .dark ? 0.07 : 0.045), .clear],
                           center: .bottomLeading, startRadius: 2, endRadius: 290)
        }.allowsHitTesting(false)
    }
}

private struct ControlGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isLayoutSnapshot) private var layoutSnapshot
    var radius: CGFloat
    var tint: Color?
    var interactive: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || layoutSnapshot {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.12), lineWidth: 0.75))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
        }
    }
}

struct GlassCluster<Content: View>: View {
    @Environment(\.isLayoutSnapshot) private var layoutSnapshot
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *), !layoutSnapshot { GlassEffectContainer(spacing: spacing) { content } }
        else { content }
    }
}

private struct QuietSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat
    func body(content: Content) -> some View {
        content.background(Color.primary.opacity(scheme == .dark ? 0.045 : 0.035), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.055), lineWidth: 0.6))
    }
}

private struct HoverHighlight: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    var radius: CGFloat
    func body(content: Content) -> some View {
        content.background(Color.primary.opacity(hovered && isEnabled ? 0.045 : 0), in: RoundedRectangle(cornerRadius: radius))
            .onHover { hovered = $0 }
    }
}

extension View {
    func controlGlass(radius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(ControlGlass(radius: radius, tint: tint, interactive: interactive))
    }
    func quietSurface(radius: CGFloat = 18) -> some View { modifier(QuietSurface(radius: radius)) }
    func hoverHighlight(radius: CGFloat = 12) -> some View { modifier(HoverHighlight(radius: radius)) }
}

struct CompanionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12).frame(height: 29)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? CMFStyle.accentInk : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.065),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(prominent ? Color.white.opacity(0.12) : Color.primary.opacity(0.06), lineWidth: 0.6))
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.38)
    }
}

struct SettingIcon: View {
    var symbol: String
    var accented = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .medium))
            .foregroundStyle(accented ? (scheme == .dark ? CMFStyle.accentLight : CMFStyle.accentInk) : Color.primary.opacity(0.7))
            .frame(width: 34, height: 34)
            .background(accented ? CMFStyle.accent.opacity(0.1) : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    var title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 14, weight: .semibold)).tracking(-0.2)
            Spacer(minLength: 5)
            if let detail { Text(detail).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
        }
    }
}

struct FinePrint: View {
    var text: String
    var symbol = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol).font(.system(size: 10)).padding(.top, 1)
            Text(text).font(.system(size: 10)).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Original code-drawn accessory illustration, not a photographic product rendering.
struct BudsPortrait: View {
    var connected: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Ellipse().fill(CMFStyle.accent.opacity(connected ? 0.17 : 0.035))
                .frame(width: 122, height: 58).blur(radius: 19).offset(y: 21)
            Circle().strokeBorder(CMFStyle.accent.opacity(connected ? 0.10 : 0.035), lineWidth: 0.7)
                .frame(width: 111, height: 111)
            Circle().trim(from: 0.03, to: 0.32).stroke(CMFStyle.accent.opacity(connected ? 0.25 : 0.05), lineWidth: 1.2)
                .frame(width: 110, height: 110).rotationEffect(.degrees(-92))
            SculptedBud(mirrored: false, connected: connected).rotationEffect(.degrees(-18)).offset(x: -25, y: 2)
                .shadow(color: .black.opacity(scheme == .dark ? 0.38 : 0.16), radius: 7, x: 0, y: 10)
            SculptedBud(mirrored: true, connected: connected).rotationEffect(.degrees(19)).offset(x: 25, y: -8)
                .shadow(color: .black.opacity(scheme == .dark ? 0.36 : 0.14), radius: 7, x: 0, y: 10)
        }.frame(width: 146, height: 112).saturation(connected ? 1 : 0).accessibilityHidden(true)
    }
}

private struct SculptedBud: View {
    var mirrored: Bool
    var connected: Bool
    private var color: Color { connected ? CMFStyle.accent : Color.gray }
    var body: some View {
        ZStack(alignment: .top) {
            Capsule().fill(LinearGradient(stops: [
                .init(color: color.opacity(0.95), location: 0),
                .init(color: connected ? Color(red: 0.78, green: 0.20, blue: 0.05) : .gray, location: 0.65),
                .init(color: connected ? Color(red: 0.98, green: 0.40, blue: 0.17) : .gray.opacity(0.7), location: 1)
            ], startPoint: .leading, endPoint: .trailing))
                .frame(width: 15, height: 58).offset(x: 9, y: 23)
            Capsule().fill(.white.opacity(0.3)).frame(width: 1.4, height: 38).offset(x: 14, y: 32)
            Ellipse().fill(Color.black.opacity(0.7)).frame(width: 17, height: 23).offset(x: -16, y: 9)
            Ellipse().fill(LinearGradient(colors: [connected ? Color(red: 1, green: 0.58, blue: 0.36) : .gray.opacity(0.7), color,
                                                  connected ? Color(red: 0.75, green: 0.18, blue: 0.035) : .gray],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 42, height: 34)
                .overlay { Ellipse().strokeBorder(.white.opacity(0.25), lineWidth: 0.7).padding(1) }
            Ellipse().fill(Color.black.opacity(0.72)).frame(width: 8, height: 14).rotationEffect(.degrees(28)).offset(x: -9, y: 9)
            Ellipse().fill(.white.opacity(0.12)).frame(width: 2, height: 8).rotationEffect(.degrees(28)).offset(x: -10, y: 9)
            Capsule().fill(.black.opacity(0.46)).frame(width: 8, height: 2).rotationEffect(.degrees(-15)).offset(x: 7, y: 8)
            Circle().fill(.black.opacity(0.4)).frame(width: 2.3, height: 2.3).offset(x: 9, y: 72)
        }.frame(width: 48, height: 85).scaleEffect(x: mirrored ? -1 : 1, y: 1)
    }
}

struct EQMotif: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array([10.0, 19, 27, 16, 23].enumerated()), id: \.offset) { _, height in
                Capsule().fill(LinearGradient(colors: [CMFStyle.accent.opacity(0.45), CMFStyle.accent],
                                             startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: height)
            }
        }.frame(width: 40, height: 40).accessibilityHidden(true)
    }
}

struct NativeMenuChoice {
    var title: String
    var symbol = "circle"
    var selected = false
    var enabled = true
    var separated = false
    var action: () -> Void
}

/// The visible setting row keeps its existing layout. Its single native keyboard stop
/// presents the shared Glass list in the popover's own window.
struct NativeChoiceMenu: View {
    var label: String
    var value: String
    var enabled: Bool
    var heading: String? = nil
    var choices: [NativeMenuChoice]
    var body: some View {
        GlassListMenu(label: label, value: value, enabled: enabled,
                      page: GlassListPage(title: heading ?? label.uppercased(), items: choices.map { choice in
            GlassListItem(id: choice.title, title: choice.title, symbol: choice.symbol,
                          selected: choice.selected, enabled: choice.enabled,
                          separated: choice.separated, action: choice.action)
        }))
        .disabled(!enabled)
    }
}
