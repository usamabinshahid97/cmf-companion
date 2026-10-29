import AppKit
import BudsCore
import CoreBluetooth
import IOBluetooth

final class BluetoothTransport: NSObject, CBCentralManagerDelegate {
    enum State: String {
        case permission = "Allow Bluetooth access"
        case denied = "Bluetooth access is off"
        case poweredOff = "Bluetooth is off"
        case searching = "Waiting for your buds"
        case notPaired = "Pair CMF Buds 2 first"
        case connecting = "Connecting…"
        case controlUnavailable = "Controls unavailable"
        case repairing = "Reconnecting Bluetooth…"
        case connected = "Connected"
    }
    var onState: ((State) -> Void)?
    var onFrame: ((BudsFrame) -> Void)?
    var onLog: ((String) -> Void)?
    private(set) var state: State = .permission {
        didSet { if oldValue != state { onState?(state) } }
    }
    private var central: CBCentralManager?
    private let permissionQueue = DispatchQueue(label: "local.cmfcompanion.bluetooth-permission")
    private var device: IOBluetoothDevice?
    private var attempt: RFCOMMAttempt?
    private var repair: DeviceReconnect?
    private var parser = BudsFrameParser()
    private var timer: Timer?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var wakeObserver: NSObjectProtocol?
    private var recovery = ControlConnectionRecovery()
    private var running = false
    private var bluetoothOn = false
    private var manualConnect = false
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        guard !running else { return }
        running = true
        // Request permission off the UI thread, before making any IOBluetooth calls.
        permissionQueue.async { [weak self] in
            guard let self else { return }
            self.central = CBCentralManager(delegate: self, queue: self.permissionQueue,
                                            options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        let watchdog = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        timer = watchdog
        RunLoop.main.add(watchdog, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.recovery.retryNow(); self?.tick() }
    }

    func stop() {
        guard running else { return }
        running = false
        recovery.reset()
        timer?.invalidate(); timer = nil
        connectNotification?.unregister(); connectNotification = nil
        disconnectNotification?.unregister(); disconnectNotification = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        dropConnection()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let poweredOn = central.state == .poweredOn
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.bluetoothOn = poweredOn
            self.tick()
        }
    }

    func connect() {
        manualConnect = true
        recovery.retryNow()
        tick()
    }

    func reconnect() {
        dropConnection()
        recovery.reset()
        state = .searching
        connect()
    }

    // Called only after the user confirms the brief audio interruption in the app.
    func repairBluetooth() {
        guard running, CBManager.authorization == .allowedAlways, bluetoothOn,
              let candidate = pairedBuds().first(where: { $0.isConnected() }) ?? device else { return }
        dropConnection()
        state = .repairing
        let recovery = DeviceReconnect(device: candidate)
        repair = recovery
        onLog?("User requested a Bluetooth reconnect for CMF Buds 2")
        recovery.onComplete = { [weak self, weak recovery] success in
            guard let self, let recovery, self.running, self.repair === recovery else { return }
            self.repair = nil
            self.recovery.reset()
            if success { self.recovery.observedConnection(to: recovery.device.controlIdentity) }
            self.manualConnect = success
            self.state = success ? .connecting : .searching
            self.onLog?(success ? "Bluetooth reconnected; refreshing the control service" : "Bluetooth reconnect did not complete")
            self.tick()
        }
        recovery.start()
    }

    private func pairedBuds() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
            ($0.name ?? "").lowercased().trimmingCharacters(in: .whitespaces).hasSuffix("cmf buds 2")
        }
    }

    private func tick() {
        guard running else { return }
        switch CBManager.authorization {
        case .notDetermined: state = .permission; return
        case .denied, .restricted: dropConnection(); recovery.reset(); state = .denied; return
        case .allowedAlways: break
        @unknown default: dropConnection(); recovery.reset(); state = .denied; return
        }
        guard bluetoothOn else { dropConnection(); recovery.reset(); state = .poweredOff; return }
        if connectNotification == nil {
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        }
        if let repair {
            if now - repair.started > 35 { repair.finish(success: repair.device.isConnected()) }
            return
        }
        if let attempt {
            attempt.link.checkConnection()
            if state == .connected {
                // An open channel is stronger evidence than the device's cached
                // connected flag. Real disconnect/close notifications also clear it.
                if attempt.link.channel?.isOpen() != true {
                    connectionLost("Control connection closed while the buds were asleep")
                }
            } else if attempt.deadline.hasExpired(at: now) {
                failed("\(attempt.stageName) timed out without a completion")
            }
            return
        }
        let paired = pairedBuds()
        let snapshot = paired.map { ControlConnectionRecovery.Device(id: $0.controlIdentity, connected: $0.isConnected()) }
        guard let target = recovery.candidate(in: snapshot, manual: manualConnect),
              let listed = paired.first(where: { $0.controlIdentity == target }) else {
            state = paired.isEmpty ? .notPaired : .searching
            return
        }
        guard recovery.canAttempt(at: now) else { return }
        // A connect notification can carry a fresher wrapper than pairedDevices().
        let candidate = device.flatMap { $0.controlIdentity == target && $0.isConnected() ? $0 : nil } ?? listed
        manualConnect = false
        if candidate !== device || disconnectNotification == nil {
            disconnectNotification?.unregister()
            device = candidate
            disconnectNotification = candidate.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        }
        parser.reset()
        if recovery.failures == 0 { state = .connecting }
        if !candidate.isConnected() { onLog?("Retrying the known buds after a transient Bluetooth status change") }
        let opening = RFCOMMAttempt(device: candidate)
        attempt = opening
        opening.onLog = { [weak self] in self?.onLog?($0) }
        opening.onConnected = { [weak self, weak opening] in
            guard let self, let opening, self.running, self.attempt === opening else { return }
            self.recovery.retryNow()
            self.state = .connected
            self.onLog?("NT LINK connected")
        }
        opening.onFailure = { [weak self, weak opening] message in
            guard let self, let opening, self.attempt === opening else { return }
            self.failed(message)
        }
        opening.onClosed = { [weak self, weak opening] in
            guard let self, let opening, self.attempt === opening else { return }
            self.connectionLost("Control connection closed")
        }
        opening.onBytes = { [weak self, weak opening] bytes in
            guard let self, let opening, self.attempt === opening, self.state == .connected else { return }
            for frame in self.parser.feed(bytes) { self.onFrame?(frame) }
        }
        opening.start()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification!, device connected: IOBluetoothDevice!) {
        guard let connected,
              (connected.name ?? "").lowercased().hasSuffix("cmf buds 2") else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, connected.isConnected() else { return }
            if let attempt = self.attempt, !connected.isSameControlDevice(as: attempt.device) { return }
            if self.attempt == nil { self.device = connected }
            self.recovery.observedConnection(to: connected.controlIdentity)
            self.tick()
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification!, device disconnected: IOBluetoothDevice!) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, let disconnected, let device = self.device,
                  disconnected.isSameControlDevice(as: device), disconnected.isConnected() == false,
                  self.repair == nil else { return }
            self.recovery.observedDisconnection(from: disconnected.controlIdentity)
            self.connectionLost("Buds disconnected from this Mac")
        }
    }

    private func dropConnection() {
        repair?.cancel(); repair = nil
        let previous = attempt
        attempt = nil
        previous?.cancel()
        // Keep the old delegate alive across queued IOBluetooth notifications.
        if let previous { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { withExtendedLifetime(previous) {} } }
        parser.reset()
    }

    private func connectionLost(_ message: String) {
        dropConnection()
        recovery.channelClosed(at: now)
        state = .searching
        onLog?(message)
    }

    private func failed(_ message: String) {
        dropConnection()
        recovery.failed(at: now)
        // A failed control attempt does not prove the buds or their audio link
        // disconnected. Keep the recovery state until a real disconnect arrives.
        state = .controlUnavailable
        onLog?(message)
    }

    func send(_ frame: BudsFrame) -> Bool {
        guard state == .connected, let channel = attempt?.link.channel else { return false }
        var bytes = BudsWire.encode(frame)
        let result = bytes.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
        guard result == kIOReturnSuccess else {
            let failedAttempt = attempt
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attempt === failedAttempt, self.running else { return }
                self.failed(String(format: "Control write failed (0x%08X)", UInt32(bitPattern: result)))
            }
            return false
        }
        return true
    }
}

/// A unique SDP target and channel delegate for one attempt, never reused for a retry.
private final class RFCOMMAttempt: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let device: IOBluetoothDevice
    var onConnected: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onClosed: (() -> Void)?
    var onBytes: (([UInt8]) -> Void)?
    var onLog: ((String) -> Void)?
    private(set) var deadline = ControlConnectionDeadline(at: ProcessInfo.processInfo.systemUptime)
    var stageName: String { deadline.phase == .discovery ? "Service discovery" : "Control channel opening" }
    private var cancelled = false
    private var discovering = true
    lazy var link = ControlChannelSession<IOBluetoothRFCOMMChannel>(isOpen: { $0.isOpen() }, close: { [weak self] channel in
        channel.setDelegate(nil)
        let status = channel.close()
        self?.onLog?(String(format: "Released control channel (0x%08X)", UInt32(bitPattern: status)))
    })

    init(device: IOBluetoothDevice) { self.device = device }

    func start() {
        link.onConnected = { [weak self] in self?.onConnected?() }
        link.onClosed = { [weak self] in self?.onClosed?() }
        link.onFailure = { [weak self] status in
            self?.onFailure?(status.map { String(format: "Control channel open failed (0x%08X)", UInt32(bitPattern: $0)) }
                             ?? "Bluetooth returned no control channel")
        }
        onLog?("Resolving the NT LINK control service")
        // The full query delivers completion reliably on current macOS; a UUID-scoped
        // query can return success without calling its target after the buds wake.
        let result = device.performSDPQuery(self)
        if result != kIOReturnSuccess { onFailure?(String(format: "Service discovery failed (0x%08X)", UInt32(bitPattern: result))) }
    }

    func cancel() {
        cancelled = true
        link.cancel()
        onConnected = nil; onFailure = nil; onClosed = nil; onBytes = nil
    }

    @objc func sdpQueryComplete(_ queried: IOBluetoothDevice!, status: IOReturn) {
        DispatchQueue.main.async { [weak self] in self?.discovered(queried, status: status) }
    }

    private func discovered(_ queried: IOBluetoothDevice?, status: IOReturn) {
        guard !cancelled, discovering else { return }
        guard status == kIOReturnSuccess else {
            discovering = false
            onFailure?(String(format: "Service discovery callback failed (0x%08X)", UInt32(bitPattern: status)))
            return
        }
        guard let queried, queried.isSameControlDevice(as: device) else {
            discovering = false
            onFailure?("Service discovery completed without the requested buds")
            return
        }
        discovering = false
        guard CBManager.authorization == .allowedAlways else { onFailure?("Bluetooth access was revoked"); return }
        let uuid = IOBluetoothSDPUUID(bytes: BudsWire.serviceUUID, length: BudsWire.serviceUUID.count)
        var channelID: BluetoothRFCOMMChannelID = 0
        for case let record as IOBluetoothSDPServiceRecord in queried.services ?? [] {
            var candidate: BluetoothRFCOMMChannelID = 0
            if record.hasService(from: [uuid as Any]), record.getRFCOMMChannelID(&candidate) == kIOReturnSuccess {
                channelID = candidate; break
            }
        }
        guard channelID != 0 else { onFailure?("NT LINK was not reported by the buds"); return }
        deadline.beginOpening(at: ProcessInfo.processInfo.systemUptime)
        onLog?("NT LINK discovered; opening control channel \(channelID)")
        link.open {
            var opened: IOBluetoothRFCOMMChannel?
            let result = queried.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
            return (opened, result)
        }
    }

    func rfcommChannelOpenComplete(_ opened: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.cancelled else { return }
            guard CBManager.authorization == .allowedAlways else { self.onFailure?("Bluetooth access was revoked"); return }
            self.onLog?(String(format: "Control channel completion (0x%08X; channel %@)", UInt32(bitPattern: status), opened == nil ? "missing" : "present"))
            self.link.didOpen(opened, status: status)
        }
    }

    func rfcommChannelClosed(_ closed: IOBluetoothRFCOMMChannel!) {
        guard let closed else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.cancelled else { return }
            self.link.didClose(closed)
        }
    }

    func rfcommChannelData(_ source: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard let source, let pointer, length > 0 else { return }
        let bytes = [UInt8](UnsafeRawBufferPointer(start: pointer, count: length))
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.cancelled, source === self.link.channel else { return }
            self.onBytes?(bytes)
        }
    }
}

private extension IOBluetoothDevice {
    var controlIdentity: String {
        guard let address = addressString, !address.isEmpty else {
            return "object:\(ObjectIdentifier(self))"
        }
        return "device:" + address.lowercased().replacingOccurrences(of: "-", with: ":")
    }

    func isSameControlDevice(as other: IOBluetoothDevice) -> Bool {
        self === other || controlIdentity == other.controlIdentity
    }
}

/// Reconnect only these earbuds, after an explicit in-app confirmation. Never reset the Mac's radio.
private final class DeviceReconnect: NSObject {
    let device: IOBluetoothDevice
    let started = ProcessInfo.processInfo.systemUptime
    var onComplete: ((Bool) -> Void)?
    private var cancelled = false
    init(device: IOBluetoothDevice) { self.device = device }

    func start() {
        let result = device.closeConnection()
        guard result == kIOReturnSuccess else { finish(success: false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.cancelled else { return }
            let result = self.device.openConnection(self)
            if result != kIOReturnSuccess { self.finish(success: self.device.isConnected()) }
        }
    }

    @objc func connectionComplete(_ connected: IOBluetoothDevice!, status: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.cancelled, connected === self.device else { return }
            self.finish(success: status == kIOReturnSuccess || self.device.isConnected())
        }
    }

    func finish(success: Bool) {
        guard !cancelled else { return }
        cancelled = true
        let completion = onComplete
        onComplete = nil
        completion?(success)
    }

    func cancel() { cancelled = true; onComplete = nil }
}
