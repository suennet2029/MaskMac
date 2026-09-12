func disableSettlesWithoutWaitingFourSeconds() {
    var transition = DisplayTransition(enabled: false, startedAt: 10)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 10) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 10.3) == .settled)
}

func restoreRequiresInternalDisplayToReturn() {
    var transition = DisplayTransition(enabled: true, startedAt: 0)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 0) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 1) == .waiting)
    precondition(transition.observe(internalActive: true, externalIDs: [2], now: 2) == .waiting)
    precondition(transition.observe(internalActive: true, externalIDs: [2], now: 2.3) == .settled)
}

func linkRetrainingRestartsStabilityWindow() {
    var transition = DisplayTransition(enabled: false, startedAt: 0)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 0) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [], now: 0.2) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 2.7) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 3) == .settled)
}

func changingExternalTopologyMustSettleAgain() {
    var transition = DisplayTransition(enabled: false, startedAt: 0)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 0) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [3], now: 0.2) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [3], now: 0.3) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [3], now: 0.5) == .settled)
}

func allScreensMissingNeverCountsAsSuccessfulDisable() {
    var transition = DisplayTransition(enabled: false, startedAt: 0)
    precondition(transition.observe(internalActive: false, externalIDs: [], now: 0) == .waiting)
    precondition(transition.observe(internalActive: false, externalIDs: [], now: 4) == .timedOut)
}

func unpluggedExternalDoesNotPreventInternalRecovery() {
    var transition = DisplayTransition(enabled: true, startedAt: 0)
    precondition(transition.observe(internalActive: true, externalIDs: [], now: 0) == .waiting)
    precondition(transition.observe(internalActive: true, externalIDs: [], now: 0.3) == .settled)
}

func failedRestoreIsBounded() {
    var transition = DisplayTransition(enabled: true, startedAt: 0)
    precondition(transition.observe(internalActive: false, externalIDs: [2], now: 4) == .timedOut)
}

@main
struct DisplayTransitionTests {
    static func main() {
        disableSettlesWithoutWaitingFourSeconds()
        restoreRequiresInternalDisplayToReturn()
        linkRetrainingRestartsStabilityWindow()
        changingExternalTopologyMustSettleAgain()
        allScreensMissingNeverCountsAsSuccessfulDisable()
        unpluggedExternalDoesNotPreventInternalRecovery()
        failedRestoreIsBounded()
        print("Passed 7 display transition tests.")
    }
}
