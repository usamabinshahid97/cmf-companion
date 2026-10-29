import Testing
@testable import BudsCore

private final class TestChannel {
    var open = false
    var closeCount = 0
}

private func session() -> ControlChannelSession<TestChannel> {
    ControlChannelSession(isOpen: { $0.open }, close: { $0.closeCount += 1; $0.open = false })
}

@Test func channelOpeningSupportsInlineCompletion() {
    let link = session(), channel = TestChannel()
    var connections = 0
    link.onConnected = { connections += 1 }
    link.open {
        link.didOpen(channel, status: 0)
        return (channel, 0)
    }
    #expect(link.phase == .connected)
    #expect(link.channel === channel)
    #expect(connections == 1)
    #expect(channel.closeCount == 0)
    link.didOpen(channel, status: 0)
    #expect(connections == 1)
}

@Test func channelOpeningAdoptsAlreadyOpenChannelWithoutCallback() {
    let link = session(), channel = TestChannel()
    channel.open = true
    link.open { (channel, 0) }
    #expect(link.phase == .connected)
}

@Test func abandonedOpeningCannotReviveOrCloseTheReplacement() {
    let abandoned = session(), replacement = session()
    let oldChannel = TestChannel(), newChannel = TestChannel()
    abandoned.open { (oldChannel, 0) }
    abandoned.cancel()
    replacement.open { (newChannel, 0) }
    replacement.didOpen(newChannel, status: 0)
    abandoned.didOpen(oldChannel, status: 0)
    abandoned.didClose(oldChannel)
    #expect(abandoned.phase == .closed)
    #expect(oldChannel.closeCount == 1)
    #expect(replacement.phase == .connected)
    #expect(newChannel.closeCount == 0)
}

@Test func openingFailureReleasesPartialChannelExactlyOnce() {
    let link = session(), channel = TestChannel()
    var failures: [Int32?] = []
    link.onFailure = { failures.append($0) }
    link.open { (channel, -7) }
    link.cancel()
    #expect(link.phase == .closed)
    #expect(link.channel == nil)
    #expect(channel.closeCount == 1)
    #expect(failures == [-7])
}

@Test func inlineFailureAndCloseCannotPublishAConnection() {
    for closeFirst in [false, true] {
        let link = session(), channel = TestChannel()
        var connections = 0
        link.onConnected = { connections += 1 }
        link.open {
            if closeFirst { link.didClose(channel) }
            link.didOpen(channel, status: closeFirst ? 0 : -2)
            return (channel, 0)
        }
        #expect(link.phase == .closed)
        #expect(connections == 0)
        #expect(channel.closeCount == 1)
    }
}

@Test func cancellationDuringOpenClosesReturnedChannel() {
    let link = session(), channel = TestChannel()
    link.open { link.cancel(); return (channel, 0) }
    link.didOpen(channel, status: 0)
    #expect(link.phase == .closed)
    #expect(channel.closeCount == 1)
}

@Test func closingIgnoresUnrelatedChannelsAndIsReentrantSafe() {
    let channel = TestChannel(), unrelated = TestChannel()
    var link: ControlChannelSession<TestChannel>!
    var closures = 0
    link = ControlChannelSession(isOpen: { $0.open }, close: {
        $0.closeCount += 1
        link.didClose($0)
    })
    link.onClosed = { closures += 1 }
    link.open { (channel, 0) }
    link.didOpen(channel, status: 0)
    link.didClose(unrelated)
    #expect(link.phase == .connected)
    link.didClose(channel)
    #expect(link.phase == .closed)
    #expect(closures == 1)
    #expect(channel.closeCount == 1)
}

@Test func wakingBudsGetASeparateFullChannelOpeningDeadline() {
    var deadline = ControlConnectionDeadline(at: 100)
    #expect(!deadline.hasExpired(at: 119))
    #expect(deadline.hasExpired(at: 121))
    deadline.beginOpening(at: 119)
    // The old combined 14-second timeout would already have cancelled this attempt.
    #expect(!deadline.hasExpired(at: 135))
    #expect(!deadline.hasExpired(at: 163))
    #expect(deadline.hasExpired(at: 165))
}

@Test func failedControlsBackOffWithoutHammeringBluetooth() {
    #expect((1...6).map { ControlConnectionDeadline.retryDelay(afterFailures: $0) } == [4, 8, 16, 30, 30, 30])
}

@Test func failedOpenWithoutCallbackChannelReleasesOwnedChannelImmediately() {
    let link = session(), channel = TestChannel()
    var failures: [Int32?] = []
    link.onFailure = { failures.append($0) }
    link.open { (channel, 0) }
    link.didOpen(nil, status: -7)
    #expect(link.phase == .closed)
    #expect(failures == [-7])
    #expect(channel.closeCount == 1)
    link.cancel()
    link.didOpen(nil, status: -7)
    #expect(failures.count == 1)
    #expect(channel.closeCount == 1)
}

@Test func inlineFailureWithoutCallbackChannelWaitsForOwnedResultToClose() {
    let link = session(), channel = TestChannel()
    var failures: [Int32?] = []
    link.onFailure = { failures.append($0) }
    link.open {
        link.didOpen(nil, status: -9)
        return (channel, 0)
    }
    #expect(link.phase == .closed)
    #expect(failures == [-9])
    #expect(channel.closeCount == 1)
}

@Test func missingChannelCannotPublishAFalseSuccessfulOpen() {
    let link = session(), channel = TestChannel()
    var connections = 0, failures = 0
    link.onConnected = { connections += 1 }
    link.onFailure = { _ in failures += 1 }
    link.open { (channel, 0) }
    link.didOpen(nil, status: 0)
    #expect(link.phase == .closed)
    #expect(connections == 0)
    #expect(failures == 1)
}

@Test func channelOpeningCanCompleteLaterWithoutADelegateCallback() {
    let link = session(), channel = TestChannel()
    var connections = 0
    link.onConnected = { connections += 1 }
    link.open { (channel, 0) }
    link.checkConnection()
    #expect(link.phase == .opening)
    channel.open = true
    link.checkConnection()
    link.checkConnection()
    #expect(link.phase == .connected)
    #expect(connections == 1)
    link.cancel()
    channel.open = true
    link.checkConnection()
    #expect(link.phase == .closed)
    #expect(connections == 1)
}
