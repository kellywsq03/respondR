import SwiftUI
import ARKit

/// Shared state for the app, injected into both the control window and the
/// immersive space so they stay in sync.
@Observable
@MainActor
final class AppModel {
    static let maplessCasualtyID = "mapless-gabe"
    static let fireProximityDistance: Float = 1
    static let fireExposureGracePeriod: TimeInterval = 3
    static let healthDrainRate: Double = 0.03

    var immersiveSpaceOpen: Bool = false
    var meshVisible: Bool = true
    var wireframeColor: Color = Color(red: 0.75, green: 1.0, blue: 0.15)
    var errorMessage: String? = nil
    var statusMessage: String? = nil
    var exportHandler: (@MainActor () -> String)? = nil

    /// Cell count of the saved room map on disk (nil = no map saved).
    var roomMapSurfaceCount: Int? = RoomMapStore.load()?.cellCount
    /// True once this session has re-aligned the saved map to the real room.
    var roomMapRestored: Bool = false
    var saveRoomMapHandler: (@MainActor () async -> String)? = nil
    var deleteRoomMapHandler: (@MainActor () async -> String)? = nil

    var hasRoomMap: Bool { roomMapSurfaceCount != nil }

    /// Head-locked action prompt. World-space gaze targets out in the room
    /// compete with scanned geometry and the objects themselves; this prompt
    /// rides in front of the learner like the status HUD, so picking things up
    /// never depends on hitting a small target across the room.
    enum ActionPrompt: Equatable {
        case pickUpExtinguisher(inRange: Bool, metres: Float)
        case rescueVictim(inRange: Bool, metres: Float)

        var isInRange: Bool {
            switch self {
            case .pickUpExtinguisher(let inRange, _), .rescueVictim(let inRange, _): inRange
            }
        }
    }

    var actionPrompt: ActionPrompt? = nil
    /// How close the learner must be before the victim can be rescued, so the
    /// scenario still requires walking to them.
    static let victimRescueDistance: Float = 2.5

    enum Mode: String, CaseIterable, Identifiable {
        case wireframe = "Wireframe"
        case fire = "Fire"
        var id: String { rawValue }
    }

    enum FireStartPhase: Equatable {
        case awaitingFireStart
        case started
    }

    var mode: Mode = .wireframe
    /// Bumped to ask the immersive view to reset the complete scenario.
    var resetFireTrigger: Int = 0
    /// Bumped by the immersive debrief to return through the control-window lifecycle.
    var endTrainingTrigger: Int = 0
    var extinguisherPhase: FireExtinguisherSession.Phase = .waitingToSpawn
    var isExtinguisherSpraying: Bool = false
    private(set) var fireStartPhase: FireStartPhase = .awaitingFireStart

    private var scenarioSession = ScenarioSession()
    private(set) var health: Double = 1.0
    private(set) var timeNearFire: TimeInterval = 0
    private(set) var isNearFire: Bool = false

    var scenarioPhase: ScenarioSession.Phase { scenarioSession.phase }
    var scenarioOutcome: ScenarioSession.Outcome? { scenarioSession.outcome }
    var isScenarioActive: Bool { scenarioSession.phase == .active }
    var timeRemaining: TimeInterval { scenarioSession.timeRemaining }
    var totalCasualties: Int { scenarioSession.totalCasualties }
    var rescuedCasualties: Int { scenarioSession.rescuedCount }
    var remainingCasualties: Int { scenarioSession.remainingCasualties }
    var hasStartedFire: Bool { fireStartPhase == .started }

    var healthPercentage: Int {
        Int((health * 100).rounded())
    }

    var formattedTimeRemaining: String {
        let totalSeconds = max(0, Int(ceil(timeRemaining)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var casualtyProgress: String {
        "\(rescuedCasualties)/\(totalCasualties)"
    }

    var scenarioPhaseLabel: String {
        switch scenarioPhase {
        case .preparing: "Preparing"
        case .active: "Active"
        case .victory: "Victory"
        case .defeat: "Defeat"
        }
    }

    var missionGuidance: String {
        switch scenarioPhase {
        case .preparing:
            "Scenario map required before spatial training can begin."
        case .active where !hasStartedFire:
            "Stay alert — a fire can break out anywhere in the room."
        case .active where remainingCasualties == 0:
            "Casualty rescued. Return to the green beacon at your starting point."
        case .active:
            "Extinguish fires in your path, rescue the victim, and return to your starting point before time runs out."
        case .victory:
            "Training scenario complete."
        case .defeat:
            "Review the result and try again."
        }
    }

    var extinguisherGuidance: String? {
        guard isScenarioActive else { return nil }

        return switch extinguisherPhase {
        case .waitingToSpawn:
            hasStartedFire
                ? "Fire started. The extinguisher will arrive in five seconds."
                : nil
        case .available:
            "Look at the extinguisher and pinch to pick it up."
        case .equipped:
            "Pinch and hold the extinguisher to spray. Aim the white cone at the fire."
        }
    }

    /// Whether scene reconstruction is available. False in the Simulator and on
    /// unsupported devices — the UI uses this to explain why no mesh appears.
    let isSupported: Bool

    init(isSupported: Bool = SceneReconstructionProvider.isSupported) {
        self.isSupported = isSupported
    }

    func prepareScenario() {
        health = 1.0
        timeNearFire = 0
        isNearFire = false
        fireStartPhase = .awaitingFireStart
        scenarioSession.prepare()
    }

    @discardableResult
    func beginScenario(requiredCasualtyIDs: [String]) -> Bool {
        health = 1.0
        timeNearFire = 0
        isNearFire = false
        fireStartPhase = .awaitingFireStart
        do {
            try scenarioSession.start(requiredCasualtyIDs: requiredCasualtyIDs)
            errorMessage = nil
            return true
        } catch {
            scenarioSession.prepare()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func startScenarioForAvailableContent() {
        prepareScenario()
#if DEBUG
        _ = beginScenario(requiredCasualtyIDs: [Self.maplessCasualtyID])
        statusMessage = "Debug mapless training: Gabe and fires use scanned surfaces; the exit and anchor map are not loaded."
#else
        errorMessage = "The Phase 2 anchor map is not available yet. Spatial training cannot start."
#endif
    }

    func stopScenario() {
        scenarioSession.stop()
        timeNearFire = 0
        isNearFire = false
        fireStartPhase = .awaitingFireStart
    }

    func requestScenarioReset() {
        resetFireTrigger += 1
    }

    func requestEndTraining() {
        endTrainingTrigger += 1
    }

    @discardableResult
    func recordCasualtyRescue(casualtyID: String) -> Bool {
        scenarioSession.rescue(casualtyID: casualtyID)
    }

    func recordExitReached() {
        scenarioSession.reachExit()
    }

    @discardableResult
    func recordFireStarted() -> Bool {
        guard isScenarioActive, fireStartPhase == .awaitingFireStart else { return false }
        fireStartPhase = .started
        return true
    }

    /// Advances the fixed scenario countdown and fire exposure using actual
    /// elapsed time so scheduling delays do not alter the intended rates.
    func updateScenario(deltaTime: TimeInterval, isNearActiveFire: Bool) {
        guard isScenarioActive else {
            isNearFire = false
            timeNearFire = 0
            return
        }

        let elapsed = max(0, deltaTime)
        scenarioSession.advance(by: elapsed)
        guard isScenarioActive else {
            isNearFire = false
            timeNearFire = 0
            return
        }

        isNearFire = isNearActiveFire
        guard isNearActiveFire else {
            timeNearFire = 0
            return
        }

        timeNearFire += elapsed
        if timeNearFire > Self.fireExposureGracePeriod {
            health = max(0, health - Self.healthDrainRate * elapsed)
            if health == 0 {
                scenarioSession.depleteHealth()
                isNearFire = false
                timeNearFire = 0
            }
        }
    }

#if DEBUG
    func debugExpireTimer() {
        scenarioSession.expireTime()
    }

    func debugDepleteHealth() {
        guard isScenarioActive else { return }
        health = 0
        isNearFire = false
        timeNearFire = 0
        scenarioSession.depleteHealth()
    }
#endif
}
