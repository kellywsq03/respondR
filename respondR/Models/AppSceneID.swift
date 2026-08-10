import Foundation

/// Central, typo-proof identifiers for the app's scenes, shared by the scene
/// declarations in `respondRApp` and the `openWindow` / `openImmersiveSpace`
/// calls that drive them.
enum AppSceneID {
    /// The app's single volumetric window.
    static let mainWindow = "MainWindow"
    /// The mixed-immersion mesh/fire space.
    static let meshSpace = "MeshSpace"
}
