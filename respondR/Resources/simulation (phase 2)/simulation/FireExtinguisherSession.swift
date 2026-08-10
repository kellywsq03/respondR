/// Platform-independent lifecycle for one Phase 2 extinguisher session.
struct FireExtinguisherSession {
    enum Phase: Equatable {
        case waitingToSpawn
        case available
        case equipped
    }

    private(set) var phase: Phase = .waitingToSpawn
    private(set) var isSpraying = false

    mutating func didSpawn() {
        if phase == .waitingToSpawn {
            phase = .available
        }
    }

    @discardableResult
    mutating func pickUp() -> Bool {
        guard phase == .available else { return false }
        phase = .equipped
        return true
    }

    @discardableResult
    mutating func beginSpray() -> Bool {
        guard phase == .equipped else { return false }
        isSpraying = true
        return true
    }

    mutating func endSpray() {
        isSpraying = false
    }

    mutating func reset() {
        phase = .waitingToSpawn
        isSpraying = false
    }
}
