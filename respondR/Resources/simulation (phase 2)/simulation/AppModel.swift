import SwiftUI
import ARKit

/// Shared state for the app, injected into both the control window and the
/// immersive space so they stay in sync.
@Observable
@MainActor
final class AppModel {
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

    /// Whether scene reconstruction is available. False in the Simulator and on
    /// unsupported devices — the UI uses this to explain why no mesh appears.
    let isSupported: Bool

    init(isSupported: Bool = SceneReconstructionProvider.isSupported) {
        self.isSupported = isSupported
    }
}
