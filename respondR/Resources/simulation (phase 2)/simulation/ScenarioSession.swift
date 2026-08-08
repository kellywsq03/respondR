import Foundation

/// Anchor-independent mission state for the fixed Phase 2 rescue scenario.
struct ScenarioSession {
    static let duration: TimeInterval = 5 * 60

    enum Phase: Equatable {
        case preparing
        case active
        case victory
        case defeat
    }

    enum DefeatReason: Equatable {
        case timeExpired
        case healthDepleted
        case casualtiesLeftBehind
    }

    enum StartError: LocalizedError {
        case noCasualties
        case emptyCasualtyIdentifier
        case duplicateCasualtyIdentifier

        var errorDescription: String? {
            switch self {
            case .noCasualties:
                "The scenario needs at least one casualty."
            case .emptyCasualtyIdentifier:
                "Every casualty needs a stable identifier."
            case .duplicateCasualtyIdentifier:
                "Every casualty identifier must be unique."
            }
        }
    }

    struct Outcome: Equatable {
        let isVictory: Bool
        let defeatReason: DefeatReason?
        let timeUsed: TimeInterval
        let rescuedCount: Int
        let totalCasualties: Int
    }

    private(set) var phase: Phase = .preparing
    private(set) var defeatReason: DefeatReason?
    private(set) var timeRemaining: TimeInterval = duration
    private(set) var requiredCasualtyIDs: [String] = []
    private(set) var rescuedCasualtyIDs: Set<String> = []

    var totalCasualties: Int { requiredCasualtyIDs.count }
    var rescuedCount: Int { rescuedCasualtyIDs.count }
    var remainingCasualties: Int { max(0, totalCasualties - rescuedCount) }
    var nextUnrescuedCasualtyID: String? {
        requiredCasualtyIDs.first { !rescuedCasualtyIDs.contains($0) }
    }

    var outcome: Outcome? {
        guard phase == .victory || phase == .defeat else { return nil }
        return Outcome(
            isVictory: phase == .victory,
            defeatReason: defeatReason,
            timeUsed: Self.duration - timeRemaining,
            rescuedCount: rescuedCount,
            totalCasualties: totalCasualties
        )
    }

    mutating func prepare() {
        phase = .preparing
        defeatReason = nil
        timeRemaining = Self.duration
        requiredCasualtyIDs.removeAll()
        rescuedCasualtyIDs.removeAll()
    }

    mutating func start(requiredCasualtyIDs: [String]) throws {
        guard !requiredCasualtyIDs.isEmpty else {
            throw StartError.noCasualties
        }
        guard requiredCasualtyIDs.allSatisfy({ !$0.isEmpty }) else {
            throw StartError.emptyCasualtyIdentifier
        }
        guard Set(requiredCasualtyIDs).count == requiredCasualtyIDs.count else {
            throw StartError.duplicateCasualtyIdentifier
        }

        self.requiredCasualtyIDs = requiredCasualtyIDs
        rescuedCasualtyIDs.removeAll()
        timeRemaining = Self.duration
        defeatReason = nil
        phase = .active
    }

    mutating func advance(by deltaTime: TimeInterval) {
        guard phase == .active else { return }
        timeRemaining = max(0, timeRemaining - max(0, deltaTime))
        if timeRemaining == 0 {
            resolveDefeat(.timeExpired)
        }
    }

    @discardableResult
    mutating func rescue(casualtyID: String) -> Bool {
        guard phase == .active,
              requiredCasualtyIDs.contains(casualtyID)
        else { return false }
        return rescuedCasualtyIDs.insert(casualtyID).inserted
    }

    mutating func reachExit() {
        guard phase == .active else { return }
        if remainingCasualties == 0, timeRemaining > 0 {
            phase = .victory
            defeatReason = nil
        } else {
            resolveDefeat(.casualtiesLeftBehind)
        }
    }

    mutating func depleteHealth() {
        resolveDefeat(.healthDepleted)
    }

    mutating func expireTime() {
        guard phase == .active else { return }
        timeRemaining = 0
        resolveDefeat(.timeExpired)
    }

    mutating func stop() {
        prepare()
    }

    private mutating func resolveDefeat(_ reason: DefeatReason) {
        guard phase == .active else { return }
        phase = .defeat
        defeatReason = reason
    }
}
