import SwiftUI
import ARKit

/// Shared state for the app, injected into both the control window and the
/// immersive space so they stay in sync.
@Observable
@MainActor
final class AppModel {
    static let fireProximityDistance: Float = 1
    static let fireExposureGracePeriod: TimeInterval = 3
    static let healthDrainRate: Double = 0.03

    var immersiveSpaceOpen: Bool = false
    var meshVisible: Bool = true
    var wireframeColor: Color = Color(red: 0.75, green: 1.0, blue: 0.15)
    var errorMessage: String? = nil
    var statusMessage: String? = nil
    var exportHandler: (@MainActor () -> String)? = nil

    enum Mode: String, CaseIterable, Identifiable {
        case wireframe = "Wireframe"
        case fire = "Fire"
        var id: String { rawValue }
    }
    var mode: Mode = .wireframe
    /// Bumped to ask the immersive view to reset the complete scenario.
    var resetFireTrigger: Int = 0
    /// Bumped by the immersive debrief to return through the control-window lifecycle.
    var endTrainingTrigger: Int = 0
    var extinguisherPhase: FireExtinguisherSession.Phase = .waitingToSpawn
    var isExtinguisherSpraying: Bool = false

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
        case .active where remainingCasualties == 0:
            "All casualties rescued. Find the exit."
        case .active:
            "Rescue every casualty and reach the exit before time runs out. \(remainingCasualties) remaining."
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
            nil
        case .available:
            "Tap the extinguisher to pick it up."
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
        scenarioSession.prepare()
    }

    @discardableResult
    func beginScenario(requiredCasualtyIDs: [String]) -> Bool {
        health = 1.0
        timeNearFire = 0
        isNearFire = false
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
        _ = beginScenario(requiredCasualtyIDs: [
            "debug-casualty-1",
            "debug-casualty-2"
        ])
        statusMessage = "Debug event preview: no casualty, exit, fire, or map anchors are loaded."
#else
        errorMessage = "The Phase 2 anchor map is not available yet. Spatial training cannot start."
#endif
    }

    func stopScenario() {
        scenarioSession.stop()
        timeNearFire = 0
        isNearFire = false
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
    func debugRescueNextCasualty() {
        guard let casualtyID = scenarioSession.nextUnrescuedCasualtyID else { return }
        _ = scenarioSession.rescue(casualtyID: casualtyID)
    }

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
