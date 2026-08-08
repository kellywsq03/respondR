//
//  ContentView.swift
//  respondR
//
//  Created by Kelly Wang on 7/8/26.
//

import SwiftUI
import RealityKit

/// Wraps SwiftUI content in a RealityView attachment with a BillboardComponent so it
/// rotates to face the viewer as they move around the volumetric window.
/// Supports pinch-to-zoom (0.5x–2.5x).
struct BillboardedPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var panelScale: Float = 1.0
    @State private var pinchDelta: Float = 1.0

    var body: some View {
        RealityView { rvContent, attachments in
            if let panel = attachments.entity(for: "panel") {
                panel.name = "billboardPanel"
                panel.components.set(BillboardComponent())
                panel.components.set(InputTargetComponent())
                rvContent.add(panel)
            }
        } update: { rvContent, _ in
            if let panel = rvContent.entities.first(where: { $0.name == "billboardPanel" }) {
                panel.scale = SIMD3(repeating: panelScale * pinchDelta)
            }
        } attachments: {
            Attachment(id: "panel") {
                content()
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    pinchDelta = Float(value.magnification)
                }
                .onEnded { value in
                    panelScale = max(0.5, min(2.5, panelScale * Float(value.magnification)))
                    pinchDelta = 1.0
                }
        )
    }
}

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
