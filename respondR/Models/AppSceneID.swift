import Foundation

/// Central, typo-proof identifiers for the app's scenes, shared by the scene
/// declarations in `respondRApp` and the `openWindow` / `openImmersiveSpace`
/// calls that drive them.
enum AppSceneID {
    /// The Phase II control panel window (ControlWindowView).
    static let phase2Controls = "Phase2Controls"
    /// The mixed-immersion mesh/fire space.
    static let meshSpace = "MeshSpace"
}
