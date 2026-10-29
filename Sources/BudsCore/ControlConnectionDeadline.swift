/// Phase deadlines use a monotonic clock and restart when discovery finishes.
public struct ControlConnectionDeadline {
    public enum Phase { case discovery, opening }
    public private(set) var phase: Phase = .discovery
    private var started: Double

    public init(at uptime: Double) { started = uptime }

    public mutating func beginOpening(at uptime: Double) {
        phase = .opening
        started = uptime
    }

    public func hasExpired(at uptime: Double) -> Bool {
        uptime - started > (phase == .discovery ? 20 : 45)
    }

    public static func retryDelay(afterFailures count: Int) -> Double {
        switch count {
        case ...1: 4
        case 2: 8
        case 3: 16
        default: 30
        }
    }
}
