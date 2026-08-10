//
//  respondRApp.swift
//  respondR
//
//  Created by Kelly Wang on 7/8/26.
//

import SwiftUI
import RealityKit

@main
struct respondRApp: App {
    @State private var appModel = AppModel()

    init() {
        PlacedItemComponent.registerComponent()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: AppSceneID.mainWindow) {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 2.2, height: 1.0, depth: 1.5, in: .meters)

        ImmersiveSpace(id: AppSceneID.meshSpace) {
            ImmersiveMeshView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        .defaultSize(width: 0.9, height: 0.6, depth: 0.55, in: .meters)
    }
}
