import AppKit
import BudsCore
import SwiftUI

enum CompanionTab: String, CaseIterable {
    case sound = "Sound", controls = "Controls", device = "Device"
    var symbol: String {
        switch self { case .sound: "waveform"; case .controls: "hand.tap"; case .device: "earbuds" }
    }
}

struct CompanionView: View {
    @ObservedObject var model: BudsModel
    @ObservedObject private var systemAppearance = SystemAppearance.shared
    var panelHeight: CGFloat = CompanionLayout.height
    var previewAppearance: CompanionAppearance? = nil
    @State var tab: CompanionTab = .sound
    @AppStorage("companionAppearance") private var storedAppearance = CompanionAppearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigation
    @State private var side = 2
    @State private var showDevices = false
    @State private var customDraft = CustomEQ()
    @State private var bassDraft = 3.0
    @State private var ringSide: UInt8 = 2
    @State private var confirmRing = false
    @State private var confirmReconnect = false
    #if DEBUG
    @State private var previewMenuAppearance: CompanionAppearance?
    @State private var previewMenuBattery = true
    @State private var previewMenuLogin = false
    #endif

    private var appearance: CompanionAppearance {
        #if DEBUG
        if previewMenusEnabled, let previewMenuAppearance { return previewMenuAppearance }
        #endif
        return previewAppearance ?? CompanionAppearance(rawValue: storedAppearance) ?? .system
    }
    private var scheme: ColorScheme { appearance.scheme ?? systemAppearance.scheme }
    private var previewMenusEnabled: Bool {
        #if DEBUG
        return model.isPreview
            && Bundle.main.object(forInfoDictionaryKey: "CMFDesignPreview") as? Bool == true
            && Bundle.main.object(forInfoDictionaryKey: "CMFPreviewMenusEnabled") as? Bool == true
        #else
        return false
        #endif
    }
    private var menuControlsAvailable: Bool {
        model.canChange || (previewMenusEnabled && model.connected && model.pendingChange == nil
                            && (model.modelID == nil || model.modelID == "B179"))
    }
    private var accentText: Color { scheme == .dark ? CMFStyle.accentLight : CMFStyle.accentInk }
    private var transition: Animation? { reduceMotion ? nil : .smooth(duration: 0.22) }

    var body: some View {
        VStack(spacing: 0) {
            header
            navigationBar.padding(.horizontal, CompanionLayout.inset).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.connected { connectionPanel }
                    switch tab {
                    case .sound: soundPage
                    case .controls: controlsPage
                    case .device: devicePage
                    }
                }
                .padding(.horizontal, CompanionLayout.inset)
                .padding(.top, 4).padding(.bottom, 20)
            }
            .id(tab).scrollIndicators(.automatic)
            footer
        }
        .frame(width: CompanionLayout.width, height: panelHeight)
        .background { CompanionBackdrop() }
        .background { CompanionAppearanceBridge(scheme: scheme).frame(width: 0, height: 0) }
        .foregroundStyle(.primary).tint(CMFStyle.accent)
        .preferredColorScheme(scheme)
        .environment(\.colorScheme, scheme)
        .onAppear { customDraft = model.customEQ ?? CustomEQ(); bassDraft = model.bassLevel }
        .onChange(of: model.customEQ) { _, value in if let value { customDraft = value } }
        .onChange(of: model.bassLevel) { _, value in bassDraft = value }
        .onChange(of: tab) { _, _ in GlassListPresenter.shared.dismiss() }
        .onChange(of: side) { _, _ in GlassListPresenter.shared.dismiss() }
        .onDisappear { GlassListPresenter.shared.dismiss(restoreFocus: false) }
        .alert("Remove your earbuds first", isPresented: $confirmRing) {
            Button("Cancel", role: .cancel) {}
            Button("Ring \(ringSide == 2 ? "left" : "right") bud") { model.ring(ringSide) }
        } message: {
            Text("Find My Buds plays a loud sound. Take both earbuds out of your ears. The app sends a stop after 3 seconds.")
        }
        .alert("Reconnect your buds?", isPresented: $confirmReconnect) {
            Button("Cancel", role: .cancel) {}
            Button("Reconnect Bluetooth") { model.repairBluetooth() }
        } message: {
            Text("This briefly disconnects CMF Buds 2 from this Mac to clear a stuck connection. Audio will pause. Your earbud settings are kept.")
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text("cmf").font(.system(size: 19, weight: .black, design: .rounded)).tracking(-1)
                Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 12)
                Text("COMPANION").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.7)
                    .foregroundStyle(.secondary)
                Spacer()
                appMenu
            }.frame(height: 28)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Buds 2").font(.system(size: 33, weight: .semibold)).tracking(-1.2)
                    HStack(spacing: 6) {
                        if model.connection == .connecting || model.connection == .repairing {
                            ProgressView().controlSize(.mini).frame(width: 7, height: 7)
                        } else {
                            Circle().fill(model.connected ? CMFStyle.green : Color.secondary.opacity(0.65))
                                .frame(width: 5, height: 5)
                        }
                        Text(model.isPreview ? "Preview · sample data" : model.connection.rawValue)
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                BudsPortrait(connected: model.connected).padding(.trailing, 1)
            }.frame(height: 100).padding(.top, 4)

            batteryRail.padding(.top, 8).padding(.bottom, 17)
        }
        .padding(.horizontal, 24).padding(.top, 15)
    }

    private var batteryRail: some View {
        HStack(spacing: 0) {
            batteryReading("Left", symbol: "earbud.left", reading: model.battery[2])
            Rectangle().fill(CMFStyle.hairline).frame(width: 0.7, height: 26).padding(.horizontal, 13)
            batteryReading("Right", symbol: "earbud.right", reading: model.battery[3])
            Rectangle().fill(CMFStyle.hairline).frame(width: 0.7, height: 26).padding(.horizontal, 13)
            batteryReading("Case", symbol: "earbuds.case", reading: model.battery[4])
        }
    }

    private func batteryReading(_ title: String, symbol: String, reading: BatteryReading?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: title == "Case" ? 20 : 21, weight: .regular))
                .foregroundStyle(.secondary).frame(width: 23)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(reading.map { "\($0.percent)" } ?? "—")
                        .font(.system(size: 17, weight: .semibold, design: .rounded)).tracking(-0.4).monospacedDigit()
                    if reading != nil { Text("%").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
                    if reading?.charging == true { Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(accentText) }
                }
                .foregroundStyle((reading?.percent ?? 100) <= 20 ? Color.red : Color.primary)
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) battery")
        .accessibilityValue(reading.map { "\($0.percent) percent\($0.charging ? ", charging" : "")" } ?? "Not reported")
        .help(title == "Case" ? "Case battery appears only when reported, usually with the case open." : "Battery reported by your buds")
    }

    private var navigationBar: some View {
        HStack(spacing: 3) {
            ForEach(CompanionTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(transition) { tab = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                        Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 35)
                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                    .background {
                        if tab == item {
                            Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.12 : 0.075))
                                .matchedGeometryEffect(id: "tab-selection", in: navigation)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain).hoverHighlight(radius: 18)
                .accessibilityLabel(item.rawValue).accessibilityAddTraits(tab == item ? .isSelected : [])
                .help("\(item.rawValue) settings")
            }
        }
        .padding(4).controlGlass(radius: 23)
    }

    private var soundPage: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Noise control", detail: model.noise?.isANC == true ? "Quiet, your way" : nil)
                GlassCluster(spacing: 8) {
                    HStack(spacing: 9) {
                        noiseButton("Off", symbol: "speaker.slash", mode: .off, selected: model.noise == .off)
                        noiseButton("Transparency", symbol: "ear.badge.waveform", mode: .transparency, selected: model.noise == .transparency)
                        noiseButton("Cancellation", symbol: "waveform", mode: model.lastANC, selected: model.noise?.isANC == true)
                    }
                }
                if model.noise?.isANC == true {
                    ANCIntensitySelector(selection: model.noise, enabled: model.canChange || intensityPreviewEnabled) { mode in
                        #if DEBUG
                        if intensityPreviewEnabled {
                            model.noise = mode; model.lastANC = mode
                            return
                        }
                        #endif
                        model.setNoise(mode)
                    }.padding(.top, 1)
                } else if model.noise == nil {
                    Text(model.connected ? "Waiting for noise settings…" : "Noise settings appear when connected.")
                        .font(CMFStyle.detail).foregroundStyle(.secondary)
                }
            }

            equalizer

            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Sound effects")
                VStack(spacing: 0) {
                    settingRow("Ultra Bass", subtitle: "Give the low end a little more weight", symbol: "waveform.path", value: model.bassEnabled) {
                        model.setBass(enabled: $0, level: model.bassLevel)
                    }
                    if model.bassEnabled == true {
                        HStack(spacing: 10) {
                            Text("Strength").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 45, alignment: .leading)
                            Slider(value: $bassDraft, in: 1...5, step: 1) { editing in
                                if !editing { model.setBass(enabled: true, level: bassDraft) }
                            }.controlSize(.small).disabled(!model.canChange).accessibilityLabel("Ultra Bass strength")
                            Text("\(Int(bassDraft))/5").font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary).frame(width: 24)
                        }.padding(.leading, 44).padding(.trailing, 14).padding(.bottom, 11)
                    }
                    insetDivider
                    settingRow("Spatial audio", subtitle: "An immersive, fixed spatial effect", symbol: "cube.transparent", value: model.spatial) {
                        model.setSpatial($0)
                    }
                }.quietSurface()
            }
        }
    }

    private var intensityPreviewEnabled: Bool {
        #if DEBUG
        return model.isPreview && Bundle.main.object(forInfoDictionaryKey: "CMFPreviewIntensityEnabled") as? Bool == true
        #else
        return false
        #endif
    }

    private func noiseButton(_ title: String, symbol: String, mode: NoiseMode, selected: Bool) -> some View {
        Button { model.setNoise(mode) } label: {
            VStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 23, weight: .regular)).frame(height: 26)
                Text(title).font(.system(size: 10, weight: selected ? .semibold : .medium)).lineLimit(1)
            }
            .foregroundStyle(selected ? accentText : Color.primary.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 82)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accentText).padding(8)
                }
            }
            .controlGlass(radius: 18, tint: selected ? CMFStyle.accent.opacity(scheme == .dark ? 0.18 : 0.12) : nil, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .opacity(model.noise == nil ? 0.45 : 1)
        }
        .buttonStyle(.plain).disabled(!model.canChange || model.noise == nil)
        .accessibilityLabel(title == "Cancellation" ? "Noise cancellation" : title)
        .accessibilityValue(selected ? "Selected" : "Not selected").accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var equalizer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                EQMotif()
                VStack(alignment: .leading, spacing: 5) {
                    Text("EQUALIZER").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.3)
                        .foregroundStyle(.secondary)
                    Text(model.preset?.title ?? "Not reported").font(.system(size: 14, weight: .semibold)).tracking(-0.2)
                        .foregroundStyle(model.preset == nil ? Color.secondary : Color.primary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).frame(height: 72)
            .accessibilityHidden(true)
            .overlay {
                NativeChoiceMenu(label: "Equalizer profile", value: model.preset?.title ?? "Not reported",
                                 enabled: menuControlsAvailable && model.preset != nil, heading: "SOUND PROFILE",
                                 choices: EQPreset.allCases.map { preset in
                    NativeMenuChoice(title: preset.title, symbol: presetSymbol(preset), selected: model.preset == preset,
                                     separated: preset == .custom) { selectMenuPreset(preset) }
                })
            }
            .hoverHighlight(radius: 18)

            if model.preset == .custom {
                VStack(spacing: 12) {
                    Rectangle().fill(CMFStyle.hairline).frame(height: 0.6)
                    if model.customEQ != nil {
                        eqSlider("Bass", frequency: "140 Hz", value: $customDraft.bass)
                        eqSlider("Mid", frequency: "980 Hz", value: $customDraft.mid)
                        eqSlider("Treble", frequency: "6.9 kHz", value: $customDraft.treble)
                        HStack {
                            Button("Reset") { customDraft = CustomEQ() }.buttonStyle(CompanionButtonStyle()).disabled(!model.canChange)
                            Spacer()
                            Text("±6 dB").font(.system(size: 9)).foregroundStyle(.tertiary)
                            Button("Save EQ") { model.setCustomEQ(customDraft) }
                                .buttonStyle(CompanionButtonStyle(prominent: true))
                                .disabled(!model.canChange || customDraft == model.customEQ)
                        }.padding(.top, 3)
                    } else {
                        Text("Custom EQ has not been reported by your buds.")
                            .font(CMFStyle.detail).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 15)
            }
        }.quietSurface()
    }

    private func eqSlider(_ title: String, frequency: String, value: Binding<Float>) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(frequency).font(.system(size: 8)).foregroundStyle(.tertiary)
            }.frame(width: 43, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) }), in: -6...6, step: 1)
                .controlSize(.small).disabled(!model.canChange)
                .accessibilityLabel("\(title) equalizer gain").accessibilityValue(String(format: "%+.0f decibels", value.wrappedValue))
            Text(String(format: "%+.0f", value.wrappedValue))
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).frame(width: 24)
        }
    }

    private var controlsPage: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Touch controls", detail: "Made for your fingertips")
                HStack(spacing: 4) {
                    earSelector("Left bud", value: 2, symbol: "earbud.left")
                    earSelector("Right bud", value: 3, symbol: "earbud.right")
                }.padding(4).quietSurface(radius: 16)
            }

            VStack(spacing: 0) {
                let rows = model.gestures.filter { $0.side == UInt8(side) }.sorted { $0.gesture < $1.gesture }
                if rows.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.tap").font(.system(size: 25, weight: .light)).foregroundStyle(.tertiary)
                        Text(model.connected ? "Waiting for touch settings…" : "Connect your buds to edit gestures.")
                            .font(CMFStyle.detail).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 38)
                }
                ForEach(rows) { row in
                    gestureMenu(row)
                    if row.id != rows.last?.id { insetDivider }
                }
            }.quietSurface()
            FinePrint(text: "Your assignments stay on the buds and follow you to other devices. Voice assistant availability depends on the connected device.")
        }
    }

    private func earSelector(_ title: String, value: Int, symbol: String) -> some View {
        Button {
            withAnimation(transition) { side = value }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(side == value ? accentText : Color.secondary)
            .frame(maxWidth: .infinity).frame(height: 39)
            .background {
                if side == value {
                    RoundedRectangle(cornerRadius: 12).fill(CMFStyle.accent.opacity(scheme == .dark ? 0.13 : 0.09))
                        .matchedGeometryEffect(id: "ear-selection", in: navigation)
                }
            }.contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).hoverHighlight(radius: 12).accessibilityAddTraits(side == value ? .isSelected : [])
    }

    private func gestureMenu(_ row: GestureBinding) -> some View {
        HStack(spacing: 12) {
            gestureMark(row.gesture)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                Text(GestureBinding.actionTitle(row.action)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).frame(height: 65)
        .accessibilityHidden(true)
        .overlay {
            NativeChoiceMenu(label: "\(side == 2 ? "Left" : "Right") \(row.title.lowercased())",
                             value: GestureBinding.actionTitle(row.action), enabled: menuControlsAvailable,
                             heading: "\(side == 2 ? "LEFT" : "RIGHT") · \(row.title.uppercased())",
                             choices: gestureChoices(row))
        }.hoverHighlight(radius: 14)
    }

    private func gestureChoices(_ row: GestureBinding) -> [NativeMenuChoice] {
        var choices = row.allowedActions.map { action in
            NativeMenuChoice(title: GestureBinding.actionTitle(action), symbol: gestureActionSymbol(action), selected: row.action == action) {
                selectMenuGesture(row, action: action)
            }
        }
        if !row.allowedActions.contains(row.action) {
            choices.insert(NativeMenuChoice(title: GestureBinding.actionTitle(row.action), symbol: "questionmark.circle",
                                           selected: true, enabled: false, action: {}), at: 0)
        }
        return choices
    }

    private func presetSymbol(_ preset: EQPreset) -> String {
        switch preset {
        case .dirac: "waveform"
        case .rock: "guitars"
        case .electronic: "bolt"
        case .pop: "music.note"
        case .vocals: "mic"
        case .classical: "pianokeys"
        case .custom: "slider.horizontal.3"
        }
    }

    private func gestureActionSymbol(_ action: UInt8) -> String {
        switch action {
        case 1: "minus.circle"
        case 2: "playpause"
        case 8: "backward.end"
        case 9: "forward.end"
        case 10, 20, 21, 22: "waveform"
        case 11: "mic"
        case 18: "speaker.plus"
        case 19: "speaker.minus"
        default: "questionmark.circle"
        }
    }

    private func selectMenuPreset(_ preset: EQPreset) {
        guard menuControlsAvailable, model.preset != nil else { return }
        #if DEBUG
        if previewMenusEnabled { model.preset = preset; return }
        #endif
        model.setPreset(preset)
    }

    private func selectMenuGesture(_ binding: GestureBinding, action: UInt8) {
        guard menuControlsAvailable,
              let current = model.gestures.first(where: { $0.id == binding.id }),
              current.allowedActions.contains(action) else { return }
        #if DEBUG
        if previewMenusEnabled, let index = model.gestures.firstIndex(where: { $0.id == binding.id }) {
            model.gestures[index].action = action
            return
        }
        #endif
        model.setGesture(current, action: action)
    }

    private func gestureMark(_ gesture: UInt8) -> some View {
        HStack(spacing: 3) {
            let count = gesture == 3 || gesture == 9 ? 3 : 2
            ForEach(0..<count, id: \.self) { index in
                if gesture == 7 || gesture == 9, index == count - 1 {
                    Capsule().fill(accentText.opacity(0.8)).frame(width: 10, height: 4)
                } else {
                    Circle().fill(accentText.opacity(0.8)).frame(width: 4, height: 4)
                }
            }
        }.frame(width: 34, height: 34)
            .background(CMFStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
    }

    private var devicePage: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Listening preferences")
                VStack(spacing: 0) {
                    settingRow("Low latency", subtitle: "Keep games and video in sync", symbol: "bolt", value: model.latency) { model.setLatency($0) }
                    insetDivider
                    settingRow("In-ear detection", subtitle: model.inEar == nil ? "Not reported by your firmware" : "Pause when you take a bud out", symbol: "ear", value: model.inEar) { model.setInEar($0) }
                    insetDivider
                    settingRow("Dual connection", subtitle: "Stay connected to two devices", symbol: "rectangle.connected.to.line.below", value: model.dual) { model.setDual($0) }
                    if model.dual == true {
                        insetDivider
                        multipoint
                    }
                }.quietSurface()
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Fit & find")
                VStack(spacing: 0) {
                    HStack(spacing: 11) {
                        SettingIcon(symbol: "ear.badge.checkmark")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ear tip fit").font(CMFStyle.body)
                            Text(model.fitRunning ? "Testing your seal…" : "Wear both buds · plays a tone").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        if model.fitRunning {
                            Button("Stop") { model.stopFitTest() }.buttonStyle(CompanionButtonStyle())
                        } else {
                            Button("Test fit") { model.startFitTest() }.buttonStyle(CompanionButtonStyle()).disabled(!model.canChange)
                        }
                    }.padding(.horizontal, 13).padding(.vertical, 13)
                    if model.fitRunning { ProgressView().controlSize(.small).padding(.bottom, 10) }
                    if let result = model.fitResult {
                        Text(result).font(CMFStyle.detail).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).padding(.bottom, 12)
                    }
                    insetDivider
                    HStack(spacing: 11) {
                        SettingIcon(symbol: "dot.radiowaves.left.and.right")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Find My Buds").font(CMFStyle.body)
                            Text("Remove from your ears first").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if model.ringing != nil {
                            Button("Stop") { model.stopRinging() }.buttonStyle(CompanionButtonStyle(prominent: true))
                        } else {
                            HStack(spacing: 5) {
                                Button("Left") { ringSide = 2; confirmRing = true }
                                Button("Right") { ringSide = 3; confirmRing = true }
                            }.buttonStyle(CompanionButtonStyle()).disabled(!model.canChange)
                        }
                    }.padding(.horizontal, 13).padding(.vertical, 13)
                }.quietSurface()
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "About your buds")
                HStack {
                    metadata("Firmware", value: model.firmware ?? "—")
                    Spacer()
                    metadata("Model", value: model.modelID ?? "—")
                }.padding(.horizontal, 2)
                FinePrint(text: "Use Nothing X on your phone for firmware updates and phone integrations.", symbol: "arrow.up.right.square")
            }
        }
    }

    private var multipoint: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(transition) { showDevices.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Your devices").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(model.devices.isEmpty ? "Not reported" : "\(model.devices.filter(\.connected).count) connected")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showDevices ? 90 : 0))
                }.padding(.horizontal, 15).frame(height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).hoverHighlight(radius: 12)
                .accessibilityLabel("Manage connected devices").accessibilityValue(showDevices ? "Expanded" : "Collapsed")
            if showDevices {
                VStack(spacing: 12) {
                    ForEach(model.devices) { device in
                        HStack(spacing: 9) {
                            Image(systemName: device.isThisMac ? "laptopcomputer" : "iphone")
                                .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 23)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name.isEmpty ? "Remembered device" : device.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(device.isThisMac ? "This Mac" : device.connected ? "Connected" : "Not connected")
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 2)
                            if device.isThisMac {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(CMFStyle.green)
                            } else {
                                Button(device.connected ? "Disconnect" : "Connect") { model.setDevice(device, connected: !device.connected) }
                                    .buttonStyle(CompanionButtonStyle())
                                    .disabled(!model.canChange || (!device.connected && model.devices.filter(\.connected).count >= 2))
                            }
                        }
                    }
                    if model.devices.isEmpty { Text("Remembered devices appear when reported.").font(CMFStyle.detail).foregroundStyle(.secondary) }
                }.padding(.horizontal, 15).padding(.top, 5).padding(.bottom, 15)
            }
        }
    }

    private func metadata(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func settingRow(_ title: String, subtitle: String, symbol: String, value: Bool?, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 11) {
            SettingIcon(symbol: symbol, accented: value == true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(CMFStyle.body).tracking(-0.1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)
            if let value {
                Toggle(title, isOn: Binding(get: { value }, set: action))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(!model.canChange).accessibilityLabel(title)
            } else {
                Text("—").font(.system(size: 14)).foregroundStyle(.tertiary).frame(width: 32)
                    .accessibilityLabel("\(title), not reported").help("Waiting for your buds to report this setting")
            }
        }.padding(.horizontal, 13).padding(.vertical, 12)
    }

    private var insetDivider: some View { Rectangle().fill(CMFStyle.hairline).frame(height: 0.6).padding(.leading, 58).padding(.trailing, 14) }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: connectionSymbol).font(.system(size: 18, weight: .medium)).foregroundStyle(accentText).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(connectionTitle).font(.system(size: 14, weight: .semibold))
                    Text(connectionHint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                }
            }
            HStack(spacing: 7) {
                if model.connection == .searching {
                    Button("Connect to buds") { model.connect() }.buttonStyle(CompanionButtonStyle(prominent: true)).disabled(model.isPreview)
                }
                if model.connection == .controlUnavailable {
                    Button("Retry controls") { model.reconnect() }.buttonStyle(CompanionButtonStyle()).disabled(model.isPreview)
                    Button("Repair connection…") { confirmReconnect = true }
                        .buttonStyle(CompanionButtonStyle(prominent: true)).disabled(model.isPreview)
                } else if model.connection != .connecting && model.connection != .repairing {
                    Button(model.connection == .denied || model.connection == .permission ? "Bluetooth permissions" : "Bluetooth settings") {
                        openSettings(privacy: model.connection == .denied || model.connection == .permission)
                    }.buttonStyle(CompanionButtonStyle())
                }
            }.padding(.leading, 34)
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(CMFStyle.accent.opacity(scheme == .dark ? 0.075 : 0.055), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(CMFStyle.accent.opacity(0.13), lineWidth: 0.7))
    }

    private var connectionTitle: String {
        switch model.connection {
        case .permission, .denied: "Allow Bluetooth access"
        case .poweredOff: "Bluetooth is off"
        case .notPaired: "Pair your Buds 2"
        case .connecting: "Connecting to your buds"
        case .controlUnavailable: "Your controls couldn’t reconnect"
        case .repairing: "Reconnecting your buds"
        default: "Your sound is a connection away"
        }
    }
    private var connectionSymbol: String {
        switch model.connection { case .permission, .denied: "lock.shield"; case .connecting, .repairing: "antenna.radiowaves.left.and.right"; default: "earbuds" }
    }
    private var connectionHint: String {
        switch model.connection {
        case .permission: "Choose Allow in the macOS Bluetooth prompt to see your buds’ controls."
        case .denied: "Enable CMF Companion in System Settings → Privacy & Security → Bluetooth."
        case .poweredOff: "Turn on Bluetooth, then take your buds out of the case."
        case .notPaired: "Pair CMF Buds 2 in Bluetooth settings, then take both buds out of the case."
        case .connecting: "Opening the control connection. Your settings will appear as the buds report them."
        case .controlUnavailable: "The Bluetooth control connection is unavailable. We’ll keep retrying. Repair the connection if it stays stuck."
        case .repairing: "Clearing the stuck Bluetooth connection. Keep both buds awake; your controls will return when they reconnect."
        default: "Take your buds out of the case and connect them to this Mac. Controls reconnect automatically when the buds wake."
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if let pending = model.pendingChange {
                ProgressView().controlSize(.mini)
                Text("Saving \(pending.lowercased())…").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if let message = model.message {
                Image(systemName: model.messageIsError ? "exclamationmark.circle" : "checkmark.circle.fill")
                    .font(.system(size: 10)).foregroundStyle(model.messageIsError ? Color.red : CMFStyle.green)
                Text(message).font(.system(size: 10)).foregroundStyle(model.messageIsError ? Color.red : Color.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                Image(systemName: "checkmark.shield").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(model.isPreview ? "Sample data · Bluetooth is inactive" : "Settings stay with your buds")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { model.refresh(full: true) } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium)).frame(width: 27, height: 27).contentShape(Circle())
            }
            .buttonStyle(.plain).hoverHighlight(radius: 14).foregroundStyle(.secondary)
            .help("Refresh settings").accessibilityLabel("Refresh settings").disabled(!model.connected || model.isPreview)
        }
        .padding(.horizontal, 23).frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(CMFStyle.hairline).frame(height: 0.6).padding(.horizontal, 20) }
    }

    private var appMenu: some View {
        Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary).frame(width: 32, height: 28)
            .accessibilityHidden(true)
            .overlay { GlassListMenu(label: "App settings", page: appMenuPage) }
            .controlGlass(radius: 14, interactive: true)
    }

    private var menuBattery: Bool {
        #if DEBUG
        if previewMenusEnabled { return previewMenuBattery }
        #endif
        return model.showBattery
    }

    private var menuLogin: Bool {
        #if DEBUG
        if previewMenusEnabled { return previewMenuLogin }
        #endif
        return model.launchAtLogin
    }

    private var appMenuPage: GlassListPage {
        GlassListPage(title: "COMPANION", items: [
            GlassListItem(id: "reconnect", title: "Reconnect to buds", symbol: "arrow.clockwise",
                          enabled: !model.isPreview, action: { if !model.isPreview { model.reconnect() } }),
            GlassListItem(id: "bluetooth", title: "Bluetooth settings…", symbol: "antenna.radiowaves.left.and.right",
                          action: { openSettings() }),
            GlassListItem(id: "appearance", title: "Appearance", symbol: "circle.lefthalf.filled", separated: true,
                          detail: appearance.rawValue,
                          submenu: GlassListPage(title: "APPEARANCE", items: CompanionAppearance.allCases.map { item in
                GlassListItem(id: item.rawValue, title: item.rawValue,
                              symbol: item == .system ? "desktopcomputer" : (item == .light ? "sun.max" : "moon"),
                              selected: appearance == item, action: { selectMenuAppearance(item) })
            })),
            GlassListItem(id: "battery", title: "Show battery in menu bar", symbol: "battery.75percent",
                          selected: menuBattery, action: { toggleMenuBattery() }),
            GlassListItem(id: "login", title: "Launch at login", symbol: "power",
                          selected: menuLogin, action: { toggleMenuLogin() }),
            GlassListItem(id: "diagnostics", title: "Save diagnostics…", symbol: "square.and.arrow.down", separated: true,
                          action: { model.exportDiagnostics() }),
            GlassListItem(id: "about", title: "About CMF Companion", symbol: "info.circle", action: { showAbout() }),
            GlassListItem(id: "quit", title: "Quit CMF Companion", symbol: "xmark.circle", separated: true,
                          shortcut: "q", action: { NSApp.terminate(nil) })
        ])
    }

    private func selectMenuAppearance(_ item: CompanionAppearance) {
        #if DEBUG
        if previewMenusEnabled { previewMenuAppearance = item; return }
        #endif
        storedAppearance = item.rawValue
    }

    private func toggleMenuBattery() {
        #if DEBUG
        if previewMenusEnabled { previewMenuBattery.toggle(); return }
        #endif
        model.showBattery.toggle()
    }

    private func toggleMenuLogin() {
        #if DEBUG
        // The fixture demonstrates both check states without registering a login item.
        if previewMenusEnabled { previewMenuLogin.toggle(); return }
        #endif
        guard !model.isPreview else { return }
        model.setLogin(!model.launchAtLogin)
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "CMF Companion"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.2"
        alert.informativeText = "Version \(version)\nAn unofficial menu bar companion for CMF Buds 2.\n\nYour settings travel directly over Bluetooth. No account, server, or analytics.\n\nProtocol references: Ear (web), BudsLink and Nothing X Mac. See the source folder for credits and licenses."
        alert.runModal()
    }

    private func openSettings(privacy: Bool = false) {
        let address = privacy ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth" : "x-apple.systempreferences:com.apple.BluetoothSettings"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
