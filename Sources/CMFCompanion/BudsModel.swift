import AppKit
import BudsCore
import Combine
import ServiceManagement

final class BudsModel: ObservableObject {
    @Published var connection: BluetoothTransport.State = .permission
    @Published var battery: [UInt8: BatteryReading] = [:]
    @Published var noise: NoiseMode?
    @Published var lastANC: NoiseMode = .high
    @Published var preset: EQPreset?
    @Published var customEQ: CustomEQ?
    @Published var bassEnabled: Bool?
    @Published var bassLevel: Double = 3
    @Published var spatial: Bool?
    @Published var latency: Bool?
    @Published var inEar: Bool?
    @Published var dual: Bool?
    @Published var devices: [MultipointDevice] = []
    @Published var gestures: [GestureBinding] = []
    @Published var firmware: String?
    @Published var modelID: String?
    @Published var pendingChange: String?
    @Published var message: String?
    @Published var messageIsError = false
    @Published var fitResult: String?
    @Published var fitRunning = false
    @Published var ringing: UInt8?
    @Published var showBattery: Bool = UserDefaults.standard.object(forKey: "showBattery") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBattery, forKey: "showBattery") }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var log: [String] = []
    let isPreview: Bool
    private let transport = BluetoothTransport()
    private struct Request {
        var command: UInt16
        var payload: [UInt8]
        var completion: ((BudsFrame?) -> Void)?
    }
    private var queue: [Request] = []
    private var pending: (request: Request, sequence: UInt8)?
    private var sequence: UInt8 = 0
    private var timeout: Timer?
    private var poll: Timer?
    private var ringTimer: Timer?
    private var fitTimer: Timer?
    private var listPages = 0
    private var diagnosticURL: URL?
    private var receivedCount = 0
    private var session = UUID()
    private var messageToken = UUID()
    var connected: Bool { connection == .connected }
    var canChange: Bool { connected && pendingChange == nil && !isPreview && (modelID == nil || modelID == "B179") }
    var minimumBattery: Int? { [battery[2]?.percent, battery[3]?.percent].compactMap { $0 }.min() }

    init(preview: Bool = false, diagnostics: URL? = nil) {
        isPreview = preview
        diagnosticURL = diagnostics
        if preview {
            connection = .connected
            battery = BatteryReading.decode([3, 2, 84, 3, 78, 4, 0xE0]) ?? [:]
            noise = .high; preset = .dirac; customEQ = CustomEQ(); bassEnabled = true
            bassLevel = 3; spatial = false; latency = false; inEar = true; dual = true
            modelID = "B179"; firmware = "Preview"
            gestures = GestureBinding.decode([8, 2, 1, 2, 9, 2, 1, 3, 8, 2, 1, 7, 22, 2, 1, 9, 19,
                                               3, 1, 2, 9, 3, 1, 3, 8, 3, 1, 7, 22, 3, 1, 9, 18]) ?? []
            return
        }
        transport.onState = { [weak self] in self?.connectionChanged($0) }
        transport.onFrame = { [weak self] in self?.receive($0) }
        transport.onLog = { [weak self] in self?.addLog($0) }
    }

    func start() { guard !isPreview else { return }; transport.start(); writeDiagnostics() }
    func stop() {
        if ringing != nil { stopRinging() }
        if fitRunning { stopFitTest() }
        poll?.invalidate(); timeout?.invalidate(); ringTimer?.invalidate(); fitTimer?.invalidate()
        transport.stop()
    }
    func connect() { guard !isPreview else { return }; transport.connect() }
    func reconnect() { guard !isPreview else { return }; transport.reconnect() }
    func repairBluetooth() { guard !isPreview else { return }; transport.repairBluetooth() }

    private func connectionChanged(_ state: BluetoothTransport.State) {
        connection = state
        session = UUID()
        timeout?.invalidate(); timeout = nil
        let oldPending = pending
        let oldQueue = queue
        pending = nil; queue.removeAll()
        oldPending?.request.completion?(nil)
        oldQueue.forEach { $0.completion?(nil) }
        poll?.invalidate(); poll = nil
        if state == .connected {
            receivedCount = 0
            refresh(full: true)
            poll = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
                guard let self, self.pendingChange == nil else { return }
                self.refresh()
            }
        } else {
            battery = [:]; noise = nil; preset = nil; customEQ = nil; bassEnabled = nil
            spatial = nil; latency = nil; inEar = nil; dual = nil
            devices = []; gestures = []; firmware = nil; modelID = nil
            ringTimer?.invalidate(); ringing = nil
            fitTimer?.invalidate(); fitRunning = false
            if pendingChange != nil { notify("Connection lost before the setting could be confirmed.", error: true) }
            pendingChange = nil
        }
        writeDiagnostics()
    }

    func refresh(full: Bool = false) {
        guard connected, !isPreview, queue.isEmpty, pending == nil else { return }
        if full {
            enqueue(BudsCommand.protocolVersion)
            enqueue(BudsCommand.model)
            enqueue(BudsCommand.firmware)
        }
        for command in [BudsCommand.battery, BudsCommand.noise, BudsCommand.equalizer, BudsCommand.customEQ,
                        BudsCommand.bass, BudsCommand.spatial, BudsCommand.latency, BudsCommand.features,
                        BudsCommand.dual, BudsCommand.gestures] { enqueue(command) }
        refreshDevices()
    }

    private func enqueue(_ command: UInt16, _ payload: [UInt8] = [], priority: Bool = false,
                         completion: ((BudsFrame?) -> Void)? = nil) {
        guard connected else { completion?(nil); return }
        let request = Request(command: command, payload: payload, completion: completion)
        if priority { queue.insert(request, at: 0) } else { queue.append(request) }
        processQueue()
    }

    private func processQueue() {
        guard pending == nil, !queue.isEmpty, connected else { return }
        let request = queue.removeFirst()
        sequence = sequence >= 250 ? 1 : sequence + 1
        let operation = sequence
        pending = (request, operation)
        guard transport.send(BudsFrame(command: request.command, sequence: operation, payload: request.payload)) else {
            pending = nil
            request.completion?(nil)
            DispatchQueue.main.async { [weak self] in self?.processQueue() }
            return
        }
        addLog(String(format: "Sent %04X · operation %d", request.command, operation))
        timeout?.invalidate()
        let activeSession = session
        let responseTimer = Timer(timeInterval: 3.5, repeats: false) { [weak self] _ in
            guard let self, self.session == activeSession, self.pending?.sequence == operation else { return }
            self.addLog(String(format: "No reply for %04X", request.command))
            self.pending = nil
            request.completion?(nil)
            self.processQueue()
            self.writeDiagnostics()
        }
        timeout = responseTimer
        RunLoop.main.add(responseTimer, forMode: .common)
    }

    private func receive(_ frame: BudsFrame) {
        receivedCount += 1
        addLog(String(format: "Received %04X · %d bytes", frame.command, frame.payload.count))
        apply(frame)
        // Notifications and late replies must never complete an unrelated queued request.
        if let active = pending, frame.sequence == active.sequence,
           frame.command == active.request.command & 0x7FFF {
            timeout?.invalidate(); timeout = nil
            pending = nil
            active.request.completion?(frame)
            // Give the buds a little room between packets; keep the UI responsive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.processQueue() }
        }
        writeDiagnostics()
    }

    private func apply(_ frame: BudsFrame) {
        let p = frame.payload
        switch frame.command {
        case 0x4007, 0xE001, 0x6001:
            if let readings = BatteryReading.decode(p) { battery = readings }
        case 0x401E, 0xE003, 0x6003:
            if p.count >= 2, let mode = NoiseMode(rawValue: p[1]) {
                noise = mode
                if mode.isANC { lastANC = mode }
                else if p.count >= 5, let previous = NoiseMode(rawValue: p[4]), previous.isANC { lastANC = previous }
            }
        case 0x4050:
            if let raw = p.first { preset = EQPreset(rawValue: raw) }
        case 0x4044:
            if let decoded = CustomEQ.decode(p) { customEQ = decoded }
        case 0x404E:
            if p.count >= 2, p[0] <= 1, (2...10).contains(p[1]) {
                bassEnabled = p[0] == 1; bassLevel = Double(p[1]) / 2
            }
        case 0x404F:
            if let raw = p.first, raw <= 1 { spatial = raw == 1 }
        case 0x4041:
            if let raw = p.first, raw == 1 || raw == 2 { latency = raw == 1 }
        case 0x400E:
            inEar = FeatureFlags.inEar(p)
        case 0x4027, 0xE006, 0x6006:
            if let raw = p.first, raw <= 1 { dual = raw == 1 }
        case 0x4018:
            if let decoded = GestureBinding.decode(p) { gestures = decoded }
        case 0x4042:
            let value = String(decoding: p.prefix(64), as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            if !value.isEmpty { firmware = value }
        case 0x401C:
            if p.count >= 2 {
                modelID = String(format: "%04X", UInt16(p[0]) | UInt16(p[1]) << 8)
                if modelID != "B179" { notify("This device reports \(modelID!). Controls are limited to CMF Buds 2 (B179).", error: true) }
            }
        case 0xE00D, 0x600D:
            if p.count >= 2 {
                func result(_ value: UInt8) -> String { value == 0 ? "Good seal" : value == 1 ? "Adjust the ear tip" : "Try again" }
                fitResult = "Left: \(result(p[0])) · Right: \(result(p[1]))"
                fitRunning = false; fitTimer?.invalidate()
            }
        case 0xE00E, 0x600E:
            refreshDevices()
        default: break
        }
    }

    private func change(_ label: String, command: UInt16, payload: [UInt8], read: UInt16,
                        matches: @escaping (BudsFrame) -> Bool, after: (() -> Void)? = nil) {
        guard canChange else { return }
        pendingChange = label
        let activeSession = session
        enqueue(command, payload, priority: true) { [weak self] _ in
            guard let self, self.session == activeSession, self.connected else { return }
            self.verifyChange(label, read: read, matches: matches, after: after,
                              activeSession: activeSession, retries: 2)
        }
    }

    private func verifyChange(_ label: String, read: UInt16, matches: @escaping (BudsFrame) -> Bool,
                              after: (() -> Void)?, activeSession: UUID, retries: Int) {
        guard connected, session == activeSession else { return }
        enqueue(read, priority: true) { [weak self] reply in
            guard let self, self.session == activeSession else { return }
            if let reply, matches(reply) {
                self.pendingChange = nil
                self.notify("\(label) saved to your buds.")
                after?()
            } else if retries > 0 {
                // A write may notify immediately but commit a little later. Retry only the
                // read; never resend a user's write in response to a late acknowledgement.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.verifyChange(label, read: read, matches: matches, after: after,
                                       activeSession: activeSession, retries: retries - 1)
                }
            } else {
                self.pendingChange = nil
                self.notify("Couldn’t confirm \(label.lowercased()). Your buds’ reported setting is shown.", error: true)
            }
            self.writeDiagnostics()
        }
    }

    func setNoise(_ mode: NoiseMode) {
        change("Noise control", command: BudsCommand.setNoise, payload: mode.payload, read: BudsCommand.noise) {
            $0.payload.count >= 2 && $0.payload[1] == mode.rawValue
        }
    }
    func setPreset(_ preset: EQPreset) {
        change("Equalizer", command: BudsCommand.setEqualizer, payload: [preset.rawValue, 0], read: BudsCommand.equalizer) {
            $0.payload.first == preset.rawValue
        }
    }
    func setCustomEQ(_ curve: CustomEQ) {
        guard customEQ != nil else { return }
        // The editor is available only while Custom is already selected. Re-selecting the
        // preset after saving is redundant and some firmware delays that reply.
        change("Custom EQ", command: BudsCommand.setCustomEQ, payload: curve.encode(), read: BudsCommand.customEQ,
               matches: { CustomEQ.decode($0.payload) == curve })
    }
    func setBass(enabled: Bool, level: Double) {
        let raw = UInt8(min(10, max(2, (level * 2).rounded())))
        change("Ultra Bass", command: BudsCommand.setBass, payload: [enabled ? 1 : 0, raw], read: BudsCommand.bass) {
            $0.payload.count >= 2 && $0.payload[0] == (enabled ? 1 : 0) && (!enabled || $0.payload[1] == raw)
        }
    }
    func setSpatial(_ enabled: Bool) {
        change("Spatial audio", command: BudsCommand.setSpatial, payload: [enabled ? 1 : 0, 0], read: BudsCommand.spatial) {
            $0.payload.first == (enabled ? 1 : 0)
        }
    }
    func setLatency(_ enabled: Bool) {
        change("Low latency", command: BudsCommand.setLatency, payload: [enabled ? 1 : 2, 0], read: BudsCommand.latency) {
            $0.payload.first == (enabled ? 1 : 2)
        }
    }
    func setInEar(_ enabled: Bool) {
        guard inEar != nil else { return }
        change("In-ear detection", command: BudsCommand.setFeature, payload: [1, 1, enabled ? 1 : 0], read: BudsCommand.features) {
            FeatureFlags.inEar($0.payload) == enabled
        }
    }
    func setDual(_ enabled: Bool) {
        change("Dual connection", command: BudsCommand.setDual, payload: [enabled ? 1 : 0], read: BudsCommand.dual,
               matches: { $0.payload.first == (enabled ? 1 : 0) }) { [weak self] in self?.refreshDevices() }
    }
    func setGesture(_ binding: GestureBinding, action: UInt8) {
        guard binding.allowedActions.contains(action) else { return }
        var updated = binding; updated.action = action
        change("Touch control", command: BudsCommand.setGesture, payload: updated.payload, read: BudsCommand.gestures) {
            GestureBinding.decode($0.payload)?.contains(updated) == true
        }
    }

    func refreshDevices() {
        guard connected, !isPreview else { return }
        listPages = 0
        requestDevicePage(0, accumulated: [])
    }
    private func requestDevicePage(_ offset: Int, accumulated: [MultipointDevice]) {
        guard listPages < 20 else { return }
        listPages += 1
        enqueue(BudsCommand.devices, [UInt8(clamping: offset)]) { [weak self] frame in
            guard let self, let frame, let page = MultipointDevice.decodePage(frame.payload) else { return }
            var merged = accumulated
            var added = false
            for device in page {
                if let index = merged.firstIndex(where: { $0.id == device.id }) { merged[index] = device }
                else { merged.append(device); added = true }
            }
            self.devices = merged
            if added { self.requestDevicePage(merged.count, accumulated: merged) }
        }
    }
    func setDevice(_ device: MultipointDevice, connected: Bool) {
        guard canChange, !device.isThisMac else { return }
        if connected && devices.filter(\.connected).count >= 2 {
            notify("Disconnect another device before connecting a third one.", error: true); return
        }
        pendingChange = "Device connection"
        enqueue(BudsCommand.setDevice, device.payload(connect: connected), priority: true) { [weak self] frame in
            guard let self else { return }
            self.pendingChange = nil
            self.refreshDevices()
            self.notify(frame == nil ? "No acknowledgement. Refreshing the device list." : "Connection requested. Refreshing the device list.", error: frame == nil)
        }
    }

    func ring(_ side: UInt8) {
        guard canChange, [2, 3].contains(side), ringing == nil else { return }
        // Called only after the in-app remove-earbuds confirmation. Always send a stop after 3 seconds.
        ringing = side
        enqueue(BudsCommand.ring, [side, 1], priority: true) { [weak self] frame in
            if frame == nil { self?.notify("Ring command was not acknowledged. Sending stop.", error: true); self?.stopRinging() }
        }
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in self?.stopRinging() }
        ringTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stopRinging() {
        ringTimer?.invalidate(); ringTimer = nil
        guard let side = ringing else { return }
        ringing = nil
        // Cancel a start still waiting in the queue, so it cannot run after the stop.
        queue.removeAll { $0.command == BudsCommand.ring }
        sendStopImmediately(BudsCommand.ring, payload: [side, 0])
    }
    func startFitTest() {
        guard canChange, !fitRunning else { return }
        fitRunning = true; fitResult = nil
        enqueue(BudsCommand.fitTest, [1], priority: true)
        let timer = Timer(timeInterval: 15, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.fitRunning = false
            self.fitResult = "No result received. Adjust both buds and try again."
            self.stopFitTest()
        }
        fitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stopFitTest() {
        fitTimer?.invalidate(); fitRunning = false
        queue.removeAll { $0.command == BudsCommand.fitTest }
        sendStopImmediately(BudsCommand.fitTest, payload: [0])
    }
    private func sendStopImmediately(_ command: UInt16, payload: [UInt8]) {
        guard connected, !isPreview else { return }
        sequence = sequence >= 250 ? 1 : sequence + 1
        _ = transport.send(BudsFrame(command: command, sequence: sequence, payload: payload))
        addLog(String(format: "Sent immediate stop %04X", command))
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { notify("Allow CMF Companion in System Settings → Login Items.", error: true) }
        } catch { notify("Couldn’t change launch at login: \(error.localizedDescription)", error: true) }
    }
    func notify(_ text: String, error: Bool = false) {
        message = text; messageIsError = error
        let token = UUID(); messageToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 12 : 5)) { [weak self] in
            guard self?.messageToken == token else { return }; self?.message = nil
        }
    }
    private func addLog(_ entry: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        log.append("\(time)  \(entry)")
        if log.count > 180 { log.removeFirst(log.count - 180) }
        writeDiagnostics()
    }
    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CMF-Companion-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let text = "CMF Companion \(version)\nModel: \(self.modelID ?? "unknown")\nFirmware: \(self.firmware ?? "unknown")\nConnection: \(self.connection.rawValue)\n\n" + self.log.joined(separator: "\n")
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.notify("Couldn’t save diagnostics.", error: true) }
        }
    }
    private func writeDiagnostics() {
        guard let diagnosticURL else { return }
        let values: [String: Any] = [
            "connection": connection.rawValue, "framesReceived": receivedCount,
            "firmware": firmware as Any? ?? NSNull(), "model": modelID as Any? ?? NSNull(),
            "noise": noise?.title as Any? ?? NSNull(), "equalizer": preset?.title as Any? ?? NSNull(),
            "bass": bassEnabled as Any? ?? NSNull(), "bassLevel": bassLevel,
            "spatial": spatial as Any? ?? NSNull(), "latency": latency as Any? ?? NSNull(),
            "inEar": inEar as Any? ?? NSNull(), "dual": dual as Any? ?? NSNull(),
            "gestures": gestures.count, "devices": devices.count,
            "battery": battery.mapValues { $0.percent }.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value },
            "log": Array(log.suffix(60))
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: diagnosticURL, options: .atomic)
        }
    }
}
