import Foundation

struct DisplayTransition {
    enum Outcome: Equatable {
        case waiting, settled, timedOut
    }

    let enabled: Bool
    let startedAt: TimeInterval
    private var stableSince: TimeInterval?
    private var externalIDs: Set<UInt32> = []

    init(enabled: Bool, startedAt: TimeInterval) {
        self.enabled = enabled
        self.startedAt = startedAt
    }

    mutating func observe(internalActive: Bool, externalIDs: Set<UInt32>, now: TimeInterval) -> Outcome {
        let matches = internalActive == enabled && (enabled || !externalIDs.isEmpty)
        if !matches || self.externalIDs != externalIDs {
            stableSince = nil
        }
        self.externalIDs = externalIDs
        if matches {
            if stableSince == nil { stableSince = now }
            if now - (stableSince ?? now) >= 0.25 { return .settled }
        }
        return now - startedAt >= 4.0 ? .timedOut : .waiting
    }
}
