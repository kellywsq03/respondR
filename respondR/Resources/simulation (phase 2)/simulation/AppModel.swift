import SwiftUI
import ARKit

/// Shared state for the app, injected into both the control window and the
/// immersive space so they stay in sync.
@Observable
@MainActor
final class AppModel {
    static let hudDuration: TimeInterval = 5 * 60
    static let fireProximityDistance: Float = 1.5
    static let fireExposureGracePeriod: TimeInterval = 3
    static let healthDrainRate: Double = 0.10

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
    /// Bumped to ask the immersive view to reset the fire.
    var resetFireTrigger: Int = 0

    private(set) var health: Double = 1.0
    private(set) var timeRemaining: TimeInterval = hudDuration
    private(set) var timeNearFire: TimeInterval = 0
    private(set) var isNearFire: Bool = false
    private(set) var isTimerRunning: Bool = false

    var healthPercentage: Int {
        Int((health * 100).rounded())
    }

    var formattedTimeRemaining: String {
        let totalSeconds = max(0, Int(ceil(timeRemaining)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    /// Whether scene reconstruction is available. False in the Simulator and on
    /// unsupported devices — the UI uses this to explain why no mesh appears.
    let isSupported: Bool

    init(isSupported: Bool = SceneReconstructionProvider.isSupported) {
        self.isSupported = isSupported
    }

    func resetHUD() {
        health = 1.0
        timeRemaining = Self.hudDuration
        timeNearFire = 0
        isNearFire = false
    }

    func startTimer() {
        guard timeRemaining > 0 else { return }
        isTimerRunning = true
    }

    func pauseTimer() {
        isTimerRunning = false
    }

    /// Advances the countdown and fire exposure using actual elapsed time so
    /// scheduling delays don't alter the intended rates.
    func updateHUD(deltaTime: TimeInterval, isNearActiveFire: Bool) {
        let elapsed = max(0, deltaTime)

        if isTimerRunning {
            timeRemaining = max(0, timeRemaining - elapsed)
            if timeRemaining == 0 { isTimerRunning = false }
        }

        isNearFire = isNearActiveFire
        guard isNearActiveFire else {
            timeNearFire = 0
            return
        }

        timeNearFire += elapsed
        if timeNearFire > Self.fireExposureGracePeriod {
            health = max(0, health - Self.healthDrainRate * elapsed)
        }
    }
}
