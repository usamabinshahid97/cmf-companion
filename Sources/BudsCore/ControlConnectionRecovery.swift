/// Keeps a control-session retry alive when IOBluetooth temporarily loses its
/// cached connected flag. A real disconnect notification ends that recovery.
public struct ControlConnectionRecovery {
    public struct Device: Equatable {
        public var id: String
        public var connected: Bool
        public init(id: String, connected: Bool) {
            self.id = id
            self.connected = connected
        }
    }

    public private(set) var targetID: String?
    public private(set) var failures = 0
    public private(set) var retryAt: Double = 0

    public init() {}

    public mutating func candidate(in devices: [Device], manual: Bool = false) -> String? {
        let previous = devices.first { $0.id == targetID }
        let target = (previous?.connected == true ? previous : nil)
            ?? devices.first(where: \.connected)
            ?? previous
            ?? (manual ? devices.first : nil)
        guard let target else {
            // An unpaired target must not be resurrected by stale retry intent.
            if targetID != nil { reset() }
            return nil
        }
        if targetID != target.id { retryNow() }
        targetID = target.id
        return target.id
    }

    public func canAttempt(at uptime: Double) -> Bool { uptime >= retryAt }

    public mutating func failed(at uptime: Double) {
        failures += 1
        retryAt = uptime + ControlConnectionDeadline.retryDelay(afterFailures: failures)
    }

    public mutating func observedConnection(to id: String) {
        targetID = id
        retryNow()
    }

    public mutating func retryNow() {
        failures = 0
        retryAt = 0
    }

    public mutating func channelClosed(at uptime: Double) {
        failures = 0
        retryAt = uptime + 2
    }

    @discardableResult
    public mutating func observedDisconnection(from id: String) -> Bool {
        guard targetID == id else { return false }
        reset()
        return true
    }

    public mutating func reset() {
        targetID = nil
        retryNow()
    }
}
