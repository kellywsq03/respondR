import SwiftUI

@main
struct MyAppApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ControlWindowView()
                .environment(appModel)
                .frame(width: 360, height: 340)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: "MeshSpace") {
            ImmersiveMeshView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
