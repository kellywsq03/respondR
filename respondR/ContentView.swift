//
//  ContentView.swift
//  respondR
//
//  Created by Kelly Wang on 7/8/26.
//

import SwiftUI

struct ContentView: View {
    @State private var screen: AppScreen = .phaseSelection
    @State private var viewModel = SceneViewModel()

    var body: some View {
        switch screen {
        case .phaseSelection:
            PhaseSelectionView(screen: $screen)
        case .layoutSelection:
            LayoutSelectionView(screen: $screen)
        case .liveScene(let layoutID):
            SceneView(layoutID: layoutID, screen: $screen)
                .environment(viewModel)
        }
    }
}
