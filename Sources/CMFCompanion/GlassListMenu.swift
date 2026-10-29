import AppKit
import SwiftUI

struct GlassListPage {
    var title: String
    var items: [GlassListItem]
}

struct GlassListItem: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var selected = false
    var enabled = true
    var separated = false
    var detail: String? = nil
    var shortcut: String? = nil
    var submenu: GlassListPage? = nil
    var action: (() -> Void)? = nil
}

/// A native, transparent trigger preserves the entire setting row as one click target
/// and one keyboard stop. Menus live in that same window, never in another popover.
struct GlassListMenu: View {
    var label: String
    var value: String? = nil
    var enabled = true
    var page: GlassListPage

    var body: some View {
        GlassListMenuAnchor(label: label, value: value, enabled: enabled, page: page)
            .disabled(!enabled)
    }
}

private struct GlassListMenuAnchor: NSViewRepresentable {
    var label: String
    var value: String?
    var enabled: Bool
    var page: GlassListPage

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> GlassListAnchorButton {
        let button = GlassListAnchorButton()
        button.title = ""
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryPushIn)
        button.isTransparent = true
        button.focusRingType = .exterior
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        return button
    }

    func updateNSView(_ button: GlassListAnchorButton, context: Context) {
        let allowed = enabled && context.environment.isEnabled
        button.menuEnabled = allowed
        button.isEnabled = allowed
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(value)
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityEnabled(allowed)
        context.coordinator.page = page
        context.coordinator.scheme = context.environment.colorScheme
        context.coordinator.allowed = allowed
        GlassListPresenter.shared.update(page: page, anchor: button, enabled: allowed,
                                         scheme: context.environment.colorScheme)
    }

    static func dismantleNSView(_ button: GlassListAnchorButton, coordinator: Coordinator) {
        GlassListPresenter.shared.dismiss(ifAnchoredTo: button)
    }

    final class Coordinator: NSObject {
        var page = GlassListPage(title: "", items: [])
        var scheme: ColorScheme = .light
        var allowed = false
        @objc func showMenu(_ sender: GlassListAnchorButton) {
            guard allowed, sender.menuEnabled, sender.isEnabled else { return }
            GlassListPresenter.shared.present(page: page, anchor: sender, scheme: scheme)
        }
    }
}

final class GlassListAnchorButton: NSButton {
    // SwiftUI may rewrite NSControl.isEnabled after updateNSView. The independently
    // stored permission remains authoritative for pointer, keyboard, and AX actions.
    var menuEnabled = false
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 14, yRadius: 14).fill()
    }
    override func keyDown(with event: NSEvent) {
        if [UInt16(125), 126, 36, 76, 49].contains(event.keyCode), menuEnabled, isEnabled { performClick(nil) }
        else { super.keyDown(with: event) }
    }
    override func performClick(_ sender: Any?) {
        guard menuEnabled, isEnabled else { return }
        super.performClick(sender)
    }
    override func accessibilityPerformPress() -> Bool {
        guard menuEnabled, isEnabled else { return false }
        performClick(nil)
        return true
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard menuEnabled, isEnabled else { return false }
        performClick(nil)
        return true
    }
}

/// AppKit coordinates have their origin at the lower left. Prefer below the anchor,
/// then above, and give a constrained list its own scroll area instead of clipping rows.
enum GlassListPlacement {
    static func frame(anchor: NSRect, available: NSRect, desiredHeight: CGFloat) -> NSRect {
        let width = min(296, max(1, available.width))
        let gap: CGFloat = 6
        let below = max(0, anchor.minY - gap - available.minY)
        let above = max(0, available.maxY - anchor.maxY - gap)
        let opensBelow = below >= desiredHeight || (above < desiredHeight && below >= above)
        let room = opensBelow ? below : above
        // Extremely short panels still expose as much of the list as their window allows.
        let overlapAnchor = room < min(100, desiredHeight)
        let height = min(desiredHeight, overlapAnchor ? available.height : room)
        let y = opensBelow ? anchor.minY - gap - height : anchor.maxY + gap
        return NSRect(x: min(max(anchor.maxX - width, available.minX), available.maxX - width),
                      y: min(max(y, available.minY), available.maxY - height),
                      width: width, height: max(1, height))
    }
}

private final class GlassListState: ObservableObject {
    @Published var page = GlassListPage(title: "", items: [])
    @Published var highlightedID: String?
    @Published var keyboardHighlight = false
    @Published var size = NSSize(width: 296, height: 300)
    @Published var scheme: ColorScheme = .light

    var listHeight: CGFloat { max(1, size.height - 48) }
    var naturalListHeight: CGFloat {
        page.items.reduce(0) { $0 + rowHeight($1) + ($1.separated ? 15 : 0) }
        + CGFloat(max(0, page.items.count - 1)) * 2
    }
    var naturalHeight: CGFloat { 48 + naturalListHeight }
    func rowHeight(_ item: GlassListItem) -> CGFloat {
        let trailing: CGFloat = item.submenu != nil ? 67 : (item.shortcut != nil ? 29 : 17)
        let textWidth = max(30, size.width - 16 - 24 - 16 - 11 - 11 - trailing)
        let font = NSFont.systemFont(ofSize: 13, weight: item.selected ? .medium : .regular)
        let bounds = (item.title as NSString).boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                         attributes: [.font: font])
        return max(38, ceil(bounds.height) + 16)
    }
}

/// Shared per app, so a second trigger always dismisses the first list. Its shield and
/// hosting view are children of the existing popover window and cannot close it by
/// taking key-window status. Native row buttons expose AXMenuItem/selected/enabled.
final class GlassListPresenter: NSObject {
    static let shared = GlassListPresenter()
    private let state = GlassListState()
    private weak var anchor: GlassListAnchorButton?
    private weak var previousResponder: NSResponder?
    private var shield: GlassListShieldView?
    private var hosting: GlassListHostingView?
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var rootPage = GlassListPage(title: "", items: [])
    private var path: [String] = []
    private var buttons: [String: WeakGlassListButton] = [:]
    private var typeAhead = ""
    private var lastTypeTime = Date.distantPast
    private var dismissing = false
    private var pendingFocus = false

    func present(page: GlassListPage, anchor: GlassListAnchorButton, scheme: ColorScheme) {
        if self.anchor === anchor, shield != nil { dismiss(); return }
        dismiss(restoreFocus: false)
        guard anchor.menuEnabled, anchor.isEnabled, let window = anchor.window,
              let container = overlayContainer(for: anchor) else { return }
        self.anchor = anchor
        anchor.setAccessibilityExpanded(true)
        previousResponder = window.firstResponder
        rootPage = page
        path = []
        state.scheme = scheme
        state.page = page
        state.highlightedID = initialSelection(in: page)
        state.keyboardHighlight = true
        typeAhead = ""
        buttons = [:]

        let shield = GlassListShieldView(frame: container.bounds)
        shield.presenter = self
        shield.autoresizingMask = [.width, .height]
        shield.setAccessibilityElement(false)
        let hosting = GlassListHostingView(rootView: GlassListSurface(state: state, presenter: self))
        hosting.presenter = self
        hosting.setAccessibilityRole(.menu)
        hosting.setAccessibilityLabel(page.title)
        hosting.setAccessibilityElement(true)
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        shield.addSubview(hosting)
        self.shield = shield
        self.hosting = hosting
        container.addSubview(shield, positioned: .above, relativeTo: nil)
        container.menuOverlay = shield
        positionMenu()
        window.makeFirstResponder(hosting)
        requestFocus()
        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.dismiss(restoreFocus: false) },
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in self?.positionMenu() }
        ]
        var dismissOnResign = true
        #if DEBUG
        dismissOnResign = Bundle.main.object(forInfoDictionaryKey: "CMFDesignPreview") as? Bool != true
        #endif
        if dismissOnResign {
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.dismiss(restoreFocus: false) })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss(restoreFocus: false) })
        }
        // Route only this window's temporary menu keys before responder dispatch.
        // AppKit/assistive technologies may change its first responder while the list
        // is open; arrow/End/Escape/Command-Q must still reach the same active menu.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, self.shield != nil, let window, event.window === window else { return event }
            return self.handleKey(event) ? nil : event
        }
        if let clip = anchor.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                self?.dismiss()
            })
        }
        NSAccessibility.post(element: hosting, notification: .created)
    }

    func update(page: GlassListPage, anchor: GlassListAnchorButton, enabled: Bool, scheme: ColorScheme) {
        guard self.anchor === anchor, shield != nil else { return }
        guard enabled else { dismiss(); return }
        rootPage = page
        state.scheme = scheme
        hosting?.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        updateCurrentPage(preserveHighlight: true)
    }

    func dismiss(ifAnchoredTo button: GlassListAnchorButton) {
        if anchor === button { dismiss(restoreFocus: false) }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard !dismissing, let shield else { return }
        dismissing = true
        let window = shield.window
        let trigger = anchor
        trigger?.setAccessibilityExpanded(false)
        let responder = previousResponder
        if let hosting { NSAccessibility.post(element: hosting, notification: .uiElementDestroyed) }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        self.shield = nil
        hosting = nil
        buttons = [:]
        anchor = nil
        previousResponder = nil
        rootPage = GlassListPage(title: "", items: [])
        path = []
        (shield.superview as? CompanionOverlayContainerView)?.menuOverlay = nil
        shield.removeFromSuperview()
        if restoreFocus, window?.isKeyWindow == true {
            if let trigger, trigger.window === window, trigger.menuEnabled, trigger.isEnabled { window?.makeFirstResponder(trigger) }
            else { window?.makeFirstResponder(responder) }
        }
        dismissing = false
    }

    fileprivate func dismissFromPointer(_ event: NSEvent) {
        let oldAnchor = anchor
        let container = shield?.superview as? CompanionOverlayContainerView
        let location = event.locationInWindow
        dismiss()
        // Switching directly to another dropdown is one click. Other outside clicks
        // only dismiss the list, so they cannot accidentally change an earbud setting.
        if let container,
           let next = container.hitTest(container.superview?.convert(location, from: nil) ?? location) as? GlassListAnchorButton,
           next !== oldAnchor, next.menuEnabled, next.isEnabled {
            next.performClick(nil)
        }
    }

    private func overlayContainer(for view: NSView) -> CompanionOverlayContainerView? {
        var ancestor: NSView? = view
        while let current = ancestor {
            if let container = current as? CompanionOverlayContainerView { return container }
            ancestor = current.superview
        }
        return nil
    }

    private func initialSelection(in page: GlassListPage) -> String? {
        page.items.first(where: { $0.enabled && $0.selected })?.id ?? page.items.first(where: \.enabled)?.id
    }

    private func updateCurrentPage(preserveHighlight: Bool = false) {
        var page = rootPage
        var validPath: [String] = []
        for id in path {
            guard let next = page.items.first(where: { $0.id == id })?.submenu else { break }
            page = next
            validPath.append(id)
        }
        path = validPath
        if !path.isEmpty {
            if !page.items.isEmpty { page.items[0].separated = true }
            page.items.insert(GlassListItem(id: "__back", title: "Back", symbol: "chevron.left"), at: 0)
        }
        let oldHighlight = state.highlightedID
        state.page = page
        if !preserveHighlight || !page.items.contains(where: { $0.id == oldHighlight && $0.enabled }) {
            state.highlightedID = initialSelection(in: page)
        }
        hosting?.setAccessibilityLabel(page.title)
        positionMenu()
        requestFocus()
    }

    private func positionMenu() {
        guard let anchor, let shield, let hosting, let window = anchor.window else { return }
        var available = shield.bounds.insetBy(dx: 12, dy: 12)
        if let screen = window.screen {
            let inWindow = window.convertFromScreen(screen.visibleFrame)
            available = available.intersection(shield.convert(inWindow, from: nil))
        }
        guard !available.isNull, available.width > 0, available.height > 0 else { return }
        let anchorFrame = anchor.convert(anchor.bounds, to: shield)
        let width = min(296, available.width)
        if state.size.width != width { state.size.width = width }
        let frame = GlassListPlacement.frame(anchor: anchorFrame, available: available, desiredHeight: state.naturalHeight)
        if state.size != frame.size { state.size = frame.size }
        hosting.frame = frame
        hosting.layoutSubtreeIfNeeded()
    }

    fileprivate func register(_ button: GlassListRowButton, id: String) {
        buttons[id] = WeakGlassListButton(button)
        if state.highlightedID == id, state.keyboardHighlight { requestFocus() }
    }

    fileprivate var accessibleRows: [Any] {
        state.page.items.compactMap { buttons[$0.id]?.value }
    }

    fileprivate func rowTarget(at point: NSPoint, in shield: NSView) -> NSView? {
        guard let hosting, hosting.frame.contains(point) else { return nil }
        for item in state.page.items {
            guard let button = buttons[item.id]?.value, button.window != nil, !button.isHidden else { continue }
            // SwiftUI can report the whole scroll viewport as visibleRect, even
            // beyond a represented button. Only its own clipped bounds are a hit.
            let visible = button.convert(button.bounds.intersection(button.visibleRect), to: shield)
            if !visible.isEmpty, visible.contains(point) { return button }
        }
        return nil
    }

    private func requestFocus() {
        guard !pendingFocus else { return }
        pendingFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingFocus = false
            guard self.shield != nil, self.state.keyboardHighlight,
                  let id = self.state.highlightedID, let button = self.buttons[id]?.value,
                  let window = button.window else { return }
            window.makeFirstResponder(button)
            button.setAccessibilityFocused(true)
            NSAccessibility.post(element: button, notification: .focusedUIElementChanged)
        }
    }

    fileprivate func hover(_ id: String, inside: Bool) {
        if inside {
            state.keyboardHighlight = false
            state.highlightedID = state.page.items.first(where: { $0.id == id && $0.enabled })?.id
        } else if !state.keyboardHighlight, state.highlightedID == id {
            state.highlightedID = nil
        }
    }

    fileprivate func activate(_ id: String) {
        guard anchor?.menuEnabled == true, anchor?.isEnabled == true,
              let item = state.page.items.first(where: { $0.id == id }), item.enabled else { return }
        if id == "__back" { goBack(); return }
        if item.submenu != nil {
            path.append(id)
            typeAhead = ""
            state.keyboardHighlight = true
            updateCurrentPage()
            return
        }
        let action = item.action
        dismiss()
        // Save/About/settings dialogs begin only after the menu has left the window.
        performAfterDismissal(action)
    }

    private func goBack() {
        guard let prior = path.popLast() else { dismiss(); return }
        typeAhead = ""
        state.keyboardHighlight = true
        updateCurrentPage()
        state.highlightedID = prior
        requestFocus()
    }

    fileprivate func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            switch event.keyCode {
            case 53: if path.isEmpty { dismiss() } else { goBack() }; return true
            case 123: if !path.isEmpty { goBack() }; return true
            case 124:
                if let id = state.highlightedID, state.page.items.first(where: { $0.id == id })?.submenu != nil { activate(id) }
                return true
            case 125: moveHighlight(by: 1); return true
            case 126: moveHighlight(by: -1); return true
            case 115: moveToEdge(last: false); return true
            case 119: moveToEdge(last: true); return true
            case 116: moveHighlight(by: -5); return true
            case 121: moveHighlight(by: 5); return true
            case 36, 76, 49: if let id = state.highlightedID { activate(id) }; return true
            case 48:
                // A menu is one temporary keyboard group; Tab returns to its trigger.
                dismiss(); return true
            default: break
            }
            if let characters = event.characters, !characters.isEmpty,
               characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.whitespaces).union(.punctuationCharacters).contains($0) }) {
                typeSelect(characters)
                return true
            }
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q",
           let quit = rootPage.items.first(where: { $0.shortcut == "q" && $0.enabled }) {
            let action = quit.action
            dismiss()
            performAfterDismissal(action)
            return true
        }
        return false
    }

    private func performAfterDismissal(_ action: (() -> Void)?) {
        guard let action else { return }
        // AppKit may enter a nested modal/termination run loop inside an action.
        // Running that from a main-dispatch block would prevent the existing
        // asynchronous termination reply from being serviced until it returned.
        RunLoop.main.perform(inModes: [.common], block: action)
    }

    private func moveHighlight(by step: Int) {
        let enabled = state.page.items.filter(\.enabled)
        guard !enabled.isEmpty else { return }
        let current = enabled.firstIndex(where: { $0.id == state.highlightedID }) ?? (step > 0 ? -1 : 0)
        let index = ((current + step) % enabled.count + enabled.count) % enabled.count
        highlightForKeyboard(enabled[index].id)
    }

    private func moveToEdge(last: Bool) {
        let enabled = state.page.items.filter(\.enabled)
        if let item = last ? enabled.last : enabled.first { highlightForKeyboard(item.id) }
    }

    private func highlightForKeyboard(_ id: String) {
        state.keyboardHighlight = true
        state.highlightedID = id
        requestFocus()
    }

    private func typeSelect(_ characters: String) {
        let now = Date()
        if now.timeIntervalSince(lastTypeTime) > 0.8 { typeAhead = "" }
        lastTypeTime = now
        typeAhead += characters
        let enabled = state.page.items.filter { $0.enabled && $0.id != "__back" }
        let repeated = Set(typeAhead.lowercased()).count == 1
        let prefix = repeated ? String(typeAhead.suffix(1)) : typeAhead
        let current = enabled.firstIndex(where: { $0.id == state.highlightedID }) ?? -1
        let order = repeated ? Array(enabled.dropFirst(current + 1)) + Array(enabled.prefix(current + 1)) : enabled
        if let match = order.first(where: { $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .hasPrefix(prefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) }) {
            highlightForKeyboard(match.id)
        }
    }
}

private final class WeakGlassListButton {
    weak var value: GlassListRowButton?
    init(_ value: GlassListRowButton) { self.value = value }
}

private final class GlassListShieldView: NSView {
    weak var presenter: GlassListPresenter?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let row = presenter?.rowTarget(at: local, in: self) { return row }
        return super.hitTest(point) ?? self
    }
    override func mouseDown(with event: NSEvent) {
        presenter?.dismissFromPointer(event)
    }
    override func rightMouseDown(with event: NSEvent) { presenter?.dismiss() }
    override func otherMouseDown(with event: NSEvent) { presenter?.dismiss() }
    override func scrollWheel(with event: NSEvent) { presenter?.dismiss() }
}

private final class GlassListHostingView: NSHostingView<GlassListSurface> {
    weak var presenter: GlassListPresenter?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if presenter?.handleKey(event) != true { super.keyDown(with: event) }
    }
    override func accessibilityChildren() -> [Any]? { presenter?.accessibleRows }
}

private struct GlassListSurface: View {
    @ObservedObject var state: GlassListState
    var presenter: GlassListPresenter
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.page.title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5)
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).frame(height: 32).accessibilityHidden(true)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(state.page.items) { item in
                            VStack(spacing: 0) {
                                if item.separated {
                                    Rectangle().fill(Color.primary.opacity(contrast == .increased ? 0.35 : 0.1))
                                        .frame(height: 1).padding(.horizontal, 11).padding(.vertical, 7).accessibilityHidden(true)
                                }
                                GlassListRow(item: item, highlighted: state.highlightedID == item.id,
                                             height: state.rowHeight(item), presenter: presenter)
                            }.id(item.id)
                        }
                    }
                }
                .scrollIndicators(state.naturalListHeight > state.listHeight ? .automatic : .hidden)
                .frame(height: state.listHeight)
                .onChange(of: state.highlightedID) { _, id in
                    if let id, state.keyboardHighlight { scroll.scrollTo(id, anchor: nil) }
                }
                .onChange(of: state.page.title) { _, _ in
                    if let id = state.highlightedID { scroll.scrollTo(id, anchor: nil) }
                }
            }
        }
        .padding(8).frame(width: state.size.width, height: state.size.height)
        .controlGlass(radius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22)
            .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.45 : (state.scheme == .dark ? 0.17 : 0.12)), lineWidth: 0.7))
        .shadow(color: .black.opacity(state.scheme == .dark ? 0.29 : 0.16), radius: 17, x: 0, y: 12)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 3)
        .environment(\.colorScheme, state.scheme)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: state.highlightedID)
    }
}

private struct GlassListRow: View {
    var item: GlassListItem
    var highlighted: Bool
    var height: CGFloat
    var presenter: GlassListPresenter
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var accent: Color { scheme == .dark ? CMFStyle.accentLight : CMFStyle.accentInk }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.symbol).font(.system(size: 14, weight: .regular))
                .foregroundStyle(item.selected ? accent : Color.primary.opacity(0.6)).frame(width: 16)
            Text(item.title).font(.system(size: 13, weight: item.selected ? .medium : .regular))
                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.submenu != nil {
                HStack(spacing: 8) {
                    if let detail = item.detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
            } else if let shortcut = item.shortcut {
                Text("⌘\(shortcut.uppercased())").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 29, alignment: .trailing)
            } else {
                ZStack {
                    Circle().fill(accent)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(scheme == .dark ? Color.black.opacity(0.78) : .white)
                }.frame(width: 17, height: 17).opacity(item.selected ? 1 : 0)
            }
        }
        .padding(.horizontal, 12).frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: 12).fill(item.selected
                ? CMFStyle.accent.opacity(scheme == .dark ? (highlighted ? 0.22 : 0.18) : (highlighted ? 0.15 : 0.12))
                : Color.primary.opacity(highlighted && item.enabled ? (scheme == .dark ? 0.075 : 0.045) : 0))
        }
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(item.selected ? CMFStyle.accent.opacity(contrast == .increased ? 0.75 : (scheme == .dark ? 0.36 : 0.28))
                          : Color.primary.opacity(highlighted && contrast == .increased ? 0.4 : 0), lineWidth: 0.75))
        .opacity(item.enabled ? 1 : 0.42)
        .accessibilityHidden(true)
        .overlay {
            GlassListRowTarget(item: item, presenter: presenter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(!item.enabled)
        }
        .contentShape(Rectangle())
    }
}

private struct GlassListRowTarget: NSViewRepresentable {
    var item: GlassListItem
    var presenter: GlassListPresenter
    func makeNSView(context: Context) -> GlassListRowButton {
        let button = GlassListRowButton()
        button.title = ""
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.isTransparent = true
        button.focusRingType = .none
        button.target = button
        button.action = #selector(GlassListRowButton.choose)
        return button
    }
    func updateNSView(_ button: GlassListRowButton, context: Context) {
        button.presenter = presenter
        button.itemID = item.id
        button.isEnabled = item.enabled
        button.setAccessibilityElement(true)
        button.setAccessibilityChildrenInNavigationOrder([])
        button.setAccessibilityRole(.menuItem)
        button.setAccessibilityLabel(item.title)
        button.setAccessibilityValue(item.selected ? "Selected" : item.detail)
        button.setAccessibilitySelected(item.selected)
        button.setAccessibilityEnabled(item.enabled)
        button.setAccessibilityHelp(item.submenu != nil ? "Opens \(item.title.lowercased()). Press Right Arrow to open." : nil)
        presenter.register(button, id: item.id)
    }
}

private final class GlassListRowButton: NSButton {
    weak var presenter: GlassListPresenter?
    var itemID = ""
    private var hoverTracking: NSTrackingArea?
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // A button with a menu-item role can otherwise expose its NSButtonCell as a
    // second, identically named AX item. The row itself owns the label and action.
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let presenter else { return false }
        presenter.activate(itemID)
        return true
    }
    @objc func choose() {
        guard isEnabled else { return }
        presenter?.activate(itemID)
    }
    override func keyDown(with event: NSEvent) {
        if presenter?.handleKey(event) != true { super.keyDown(with: event) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds.intersection(visibleRect),
                                  options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { presenter?.hover(itemID, inside: true) }
    override func mouseExited(with event: NSEvent) { presenter?.hover(itemID, inside: false) }
}
