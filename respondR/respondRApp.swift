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
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 2.2, height: 1.0, depth: 1.5, in: .meters)
        
        WindowGroup(id: AppSceneID.phase2Controls) {
            ControlWindowView()
                .environment(appModel)
                .frame(width: 360, height: appModel.mode == .fire ? 560 : 340)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: AppSceneID.meshSpace) {
            ImmersiveMeshView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
