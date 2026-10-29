import AppKit
import BudsCore
import Combine
import SwiftUI

@main
enum CompanionApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var model: BudsModel!
    private var subscription: AnyCancellable?
    private var hostingController: NSHostingController<CompanionView>?
    private var previewAppearance: CompanionAppearance?
    private var previewHeight: CGFloat?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-previews"), arguments.count > index + 1 {
            renderPreviews(to: URL(fileURLWithPath: arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }
        var diagnostics: URL?
        if let index = arguments.firstIndex(of: "--diagnostics"), arguments.count > index + 1 {
            diagnostics = URL(fileURLWithPath: arguments[index + 1])
        }
        let designPreview = Bundle.main.object(forInfoDictionaryKey: "CMFDesignPreview") as? Bool == true
        let scenario = Bundle.main.object(forInfoDictionaryKey: "CMFPreviewScenario") as? String ?? "sound"
        model = designPreview ? makePreviewModel(scenario: scenario) : BudsModel(preview: arguments.contains("--preview"), diagnostics: diagnostics)
        previewAppearance = (Bundle.main.object(forInfoDictionaryKey: "CMFPreviewAppearance") as? String).flatMap(CompanionAppearance.init(rawValue:))
        if designPreview, let height = Bundle.main.object(forInfoDictionaryKey: "CMFPreviewHeight") as? Double {
            previewHeight = CGFloat(height)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("CMF Companion")
            let image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "CMF Buds 2")
            image?.isTemplate = true
            button.image = image
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }
        #if DEBUG
        // Background QA restores the user's foreground app after each operation.
        // Only its isolated, Bluetooth-inactive bundle stays visible across that.
        popover.behavior = designPreview ? .applicationDefined : .transient
        #else
        popover.behavior = .transient
        #endif
        popover.animates = true
        popover.delegate = self
        let height = panelHeight()
        popover.contentSize = NSSize(width: CompanionLayout.width, height: height)
        let initialTab = CompanionTab.allCases.first { $0.rawValue.lowercased() == scenario } ?? .sound
        let hosting = NSHostingController(rootView: CompanionView(model: model, panelHeight: height, previewAppearance: previewAppearance, tab: initialTab))
        hostingController = hosting
        popover.contentViewController = CompanionPopoverController(hosting: hosting, size: popover.contentSize)
        subscription = Publishers.CombineLatest3(model.$connection.removeDuplicates(),
                                                  model.$battery.removeDuplicates(),
                                                  model.$showBattery.removeDuplicates())
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatus() }
        updateStatus()
        model.start()
        #if DEBUG
        // The isolated QA bundle has no normal app window for computer-use tools to
        // discover. Show its Bluetooth-inactive popover without touching production.
        if designPreview || arguments.contains("--show") { togglePopover() }
        #else
        if arguments.contains("--show") { togglePopover() }
        #endif
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let title = model.showBattery && model.connected ? model.minimumBattery.map { " \($0)%" } ?? "" : ""
        let alpha = model.connected ? 1.0 : 0.58
        let tooltip = "CMF Companion · \(model.connection.rawValue)"
        if button.title != title { button.title = title }
        if button.alphaValue != alpha { button.alphaValue = alpha }
        if button.toolTip != tooltip { button.toolTip = tooltip }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        let height = panelHeight()
        if popover.contentSize.height != height {
            hostingController?.rootView = CompanionView(model: model, panelHeight: height, previewAppearance: previewAppearance)
            popover.contentSize = NSSize(width: CompanionLayout.width, height: height)
        }
        model.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    private func panelHeight() -> CGFloat {
        let available = (statusItem?.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        return min(previewHeight ?? CompanionLayout.height, max(1, available - 24))
    }

    func popoverDidClose(_ notification: Notification) {
        GlassListPresenter.shared.dismiss(restoreFocus: false)
        model?.stopRinging()
        if model?.fitRunning == true { model?.stopFitTest() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if !popover.isShown { togglePopover() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        model?.stop()
        // Let the asynchronous Bluetooth close reach bluetoothd before the process exits.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { model?.stop() }

    private func makePreviewModel(scenario: String) -> BudsModel {
        let sample = BudsModel(preview: true)
        sample.battery[4] = nil
        sample.bassEnabled = false; sample.spatial = true; sample.preset = .vocals
        let mac = Array("My Mac".utf8), phone = Array("Phone".utf8)
        sample.devices = MultipointDevice.decodePage([0, 0, 2, 0x11, 1, 2, 3, 4, 5, 6, UInt8(mac.count)] + mac
                                                     + [1, 6, 5, 4, 3, 2, 1, UInt8(phone.count)] + phone) ?? []
        if scenario == "custom-eq" { sample.preset = .custom }
        #if DEBUG
        if Bundle.main.object(forInfoDictionaryKey: "CMFPreviewMenusEnabled") as? Bool == true {
            switch Bundle.main.object(forInfoDictionaryKey: "CMFPreviewMenuState") as? String {
            case "unknown-gesture":
                // A current firmware action outside the allowed choices must remain
                // visible, selected, and disabled while valid replacements work.
                if !sample.gestures.isEmpty { sample.gestures[0].action = 31 }
            case "pending": sample.pendingChange = "Equalizer"
            default: break
            }
        }
        #endif
        if scenario == "disconnected" || scenario == "unknown" {
            if scenario == "disconnected" { sample.connection = .searching }
            sample.battery = [:]; sample.noise = nil; sample.preset = nil; sample.customEQ = nil
            sample.bassEnabled = nil; sample.spatial = nil; sample.latency = nil
            sample.inEar = nil; sample.dual = nil; sample.devices = []; sample.gestures = []; sample.firmware = nil; sample.modelID = nil
        }
        return sample
    }

    private func renderPreviews(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scenarios = ["sound", "controls", "device", "custom-eq", "disconnected", "unknown", "compact"]
        for appearance in [CompanionAppearance.light, .dark] {
          for scenario in scenarios {
            let sample = makePreviewModel(scenario: scenario)
            let tab = CompanionTab.allCases.first { $0.rawValue.lowercased() == scenario } ?? .sound
            let height: CGFloat = scenario == "compact" ? 580 : CompanionLayout.height
            let view = CompanionView(model: sample, panelHeight: height, previewAppearance: appearance, tab: tab)
            let hosting = NSHostingView(rootView: view.environment(\.isLayoutSnapshot, true))
            hosting.frame = NSRect(x: 0, y: 0, width: CompanionLayout.width, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            window.contentView = hosting
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            hosting.layoutSubtreeIfNeeded()
            if let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: representation)
                if let png = representation.representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent("\(scenario)-\(appearance.rawValue.lowercased()).png"))
                }
            }
            window.close()
          }
        }
    }
}

/// Own the content-controller view, rather than placing interactive siblings inside
/// NSPopover's private window container. The popover routes pointer events through
/// this view, so an open menu can intercept them before the SwiftUI content below.
private final class CompanionPopoverController: NSViewController {
    private let hosting: NSHostingController<CompanionView>
    private let size: NSSize

    init(hosting: NSHostingController<CompanionView>, size: NSSize) {
        self.hosting = hosting
        self.size = size
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = CompanionOverlayContainerView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        view = container
        addChild(hosting)
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.addSubview(hosting.view)
    }
}

final class CompanionOverlayContainerView: NSView {
    weak var menuOverlay: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let menuOverlay, bounds.contains(local), !menuOverlay.isHidden {
            // NSView.hitTest takes a point in its superview's coordinates. Even a
            // transparent part of the shield must consume this click, never a tab
            // or an earbud control drawn beneath the floating menu.
            return menuOverlay.hitTest(local) ?? menuOverlay
        }
        return super.hitTest(point)
    }
}
