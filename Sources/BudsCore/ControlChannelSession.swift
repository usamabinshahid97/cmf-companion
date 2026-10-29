/// Owns one control-channel open, including APIs that call their delegate before returning.
/// Each Bluetooth attempt gets a separate session; cancelled sessions cannot revive a link.
public final class ControlChannelSession<Channel: AnyObject> {
    public enum Phase { case idle, opening, connected, closed }
    public private(set) var phase: Phase = .idle
    public private(set) var channel: Channel?
    public var onConnected: (() -> Void)?
    public var onFailure: ((Int32?) -> Void)?
    public var onClosed: (() -> Void)?

    private let isOpen: (Channel) -> Bool
    private let close: (Channel) -> Void
    private var inOpenCall = false
    private var earlyCompletion: (Channel?, Int32)?
    private var earlyClose: Channel?

    public init(isOpen: @escaping (Channel) -> Bool, close: @escaping (Channel) -> Void) {
        self.isOpen = isOpen
        self.close = close
    }

    public func open(_ begin: () -> (channel: Channel?, status: Int32)) {
        guard phase == .idle else { return }
        phase = .opening
        inOpenCall = true
        let result = begin()
        inOpenCall = false
        // Cancellation can occur reentrantly while the backend is opening.
        guard phase == .opening else {
            if let channel = result.channel { close(channel) }
            earlyCompletion = nil; earlyClose = nil
            return
        }
        channel = result.channel
        guard result.status == 0, let channel else {
            fail(result.status == 0 ? nil : result.status)
            return
        }
        if earlyClose === channel {
            earlyCompletion = nil; earlyClose = nil
            didClose(channel)
        } else if let (opened, status) = earlyCompletion {
            earlyCompletion = nil; earlyClose = nil
            didOpen(opened, status: status)
        }
        checkConnection()
    }

    /// Some backends expose an open channel without delivering an open callback.
    /// This also covers a channel that becomes open after the async call returns.
    public func checkConnection() {
        guard phase == .opening, let channel, isOpen(channel) else { return }
        didOpen(channel, status: 0)
    }

    public func didOpen(_ opened: Channel?, status: Int32) {
        if inOpenCall, phase == .opening {
            earlyCompletion = (opened, status)
            return
        }
        guard phase == .opening else { return }
        // Some backends report an open failure without a channel object. It is
        // still a completion for this attempt, not a reason to wait for a timeout.
        guard let opened else { fail(status == 0 ? nil : status); return }
        guard opened === channel else { return }
        guard status == 0 else { fail(status); return }
        phase = .connected
        onConnected?()
    }

    public func didClose(_ closed: Channel) {
        if inOpenCall, phase == .opening {
            earlyClose = closed
            return
        }
        guard closed === channel, phase == .opening || phase == .connected else { return }
        cancel()
        onClosed?()
    }

    public func cancel() {
        phase = .closed
        earlyCompletion = nil; earlyClose = nil
        let previous = channel
        channel = nil
        // Invalidate first: close() itself may synchronously call the delegate.
        if let previous { close(previous) }
    }

    private func fail(_ status: Int32?) {
        cancel()
        onFailure?(status)
    }
}
