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
    init() {
        PlacedItemComponent.registerComponent()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 2.2, height: 1.0, depth: 1.5, in: .meters)
    }
}
