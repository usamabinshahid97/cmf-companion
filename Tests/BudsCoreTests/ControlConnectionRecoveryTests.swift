import Testing
@testable import BudsCore

private typealias Device = ControlConnectionRecovery.Device

@Test func transientDisconnectedFlagCannotStrandAnActiveRecovery() {
    var recovery = ControlConnectionRecovery()
    #expect(recovery.candidate(in: [Device(id: "buds", connected: true)]) == "buds")
    recovery.failed(at: 100)
    for tick in 101...103 {
        #expect(recovery.candidate(in: [Device(id: "buds", connected: false)]) == "buds")
        #expect(!recovery.canAttempt(at: Double(tick)))
        #expect(recovery.failures == 1)
    }
    #expect(recovery.canAttempt(at: 104))
    recovery.failed(at: 145)
    #expect(recovery.retryAt == 153)
    #expect(recovery.candidate(in: [Device(id: "buds", connected: false)]) == "buds")
}

@Test func realBudsDisconnectEndsRecoveryButUnrelatedDisconnectDoesNot() {
    var recovery = ControlConnectionRecovery()
    recovery.observedConnection(to: "buds")
    let unrelated = recovery.observedDisconnection(from: "keyboard")
    #expect(!unrelated)
    #expect(recovery.targetID == "buds")
    let expected = recovery.observedDisconnection(from: "buds")
    #expect(expected)
    #expect(recovery.candidate(in: [Device(id: "buds", connected: false)]) == nil)
}

@Test func removedPairingCannotBeRevivedByRememberedRecoveryIntent() {
    var recovery = ControlConnectionRecovery()
    recovery.observedConnection(to: "old-buds")
    recovery.failed(at: 100)
    #expect(recovery.candidate(in: [Device(id: "other-buds", connected: false)]) == nil)
    #expect(recovery.targetID == nil)
    #expect(recovery.failures == 0)
}

@Test func asleepBudsAreNotQueriedWithoutConnectionOrUserIntent() {
    var recovery = ControlConnectionRecovery()
    let asleep = [Device(id: "buds", connected: false)]
    #expect(recovery.candidate(in: asleep) == nil)
    #expect(recovery.candidate(in: asleep, manual: true) == "buds")
    recovery.failed(at: 10)
    #expect(recovery.candidate(in: asleep) == "buds")
    #expect(!recovery.canAttempt(at: 11))
}

@Test func anotherConnectedBudsDoesNotInheritPreviousTargetsBackoff() {
    var recovery = ControlConnectionRecovery()
    recovery.observedConnection(to: "first")
    recovery.failed(at: 100)
    #expect(recovery.candidate(in: [Device(id: "first", connected: false), Device(id: "second", connected: true)]) == "second")
    #expect(recovery.canAttempt(at: 101))
    #expect(recovery.failures == 0)
}

@Test func aNativeConnectionEventRecoversBeforeThePairedListRefreshes() {
    var recovery = ControlConnectionRecovery()
    recovery.observedConnection(to: "buds")
    recovery.failed(at: 100)
    recovery.observedConnection(to: "buds")
    #expect(recovery.candidate(in: [Device(id: "buds", connected: false)]) == "buds")
    #expect(recovery.canAttempt(at: 101))
}

@Test func controlChannelCloseKeepsTargetButActualDisconnectClearsIt() {
    var recovery = ControlConnectionRecovery()
    recovery.observedConnection(to: "buds")
    recovery.channelClosed(at: 10)
    #expect(recovery.targetID == "buds")
    #expect(!recovery.canAttempt(at: 11))
    #expect(recovery.canAttempt(at: 12))
    recovery.observedDisconnection(from: "buds")
    #expect(recovery.targetID == nil)
}

@Test func cachedFlagPollingCannotResetTheFailureBackoff() {
    var recovery = ControlConnectionRecovery()
    recovery.observedConnection(to: "buds")
    for failure in 1...5 {
        recovery.failed(at: Double(failure) * 100)
        let expected = recovery.retryAt
        for _ in 0..<20 {
            #expect(recovery.candidate(in: [Device(id: "buds", connected: false)]) == "buds")
            #expect(recovery.retryAt == expected)
            #expect(recovery.failures == failure)
        }
    }
    recovery.reset()
    #expect(recovery.targetID == nil)
    #expect(recovery.failures == 0)
}
