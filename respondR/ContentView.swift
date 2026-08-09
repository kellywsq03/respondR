//
//  ContentView.swift
//  respondR
//
//  Created by Kelly Wang on 7/8/26.
//

import SwiftUI
import RealityKit

/// Wraps SwiftUI content in a RealityView attachment with a BillboardComponent so it
/// rotates to face the viewer. Two-hand pinch (MagnifyGesture) zooms freely upward
/// from `initialScale`, clamped `[0.6, 5.0]`.
struct BillboardedPanel<Content: View>: View {
    let initialScale: Float
    let anchorY: Float
    @ViewBuilder let content: () -> Content
    @State private var panelScale: Float
    @State private var pinchDelta: Float = 1.0

    init(initialScale: Float = 1.8, anchorY: Float = -0.2, @ViewBuilder content: @escaping () -> Content) {
        self.initialScale = initialScale
        self.anchorY = anchorY
        self.content = content
        self._panelScale = State(initialValue: initialScale)
    }

    var body: some View {
        RealityView { rvContent, attachments in
            if let panel = attachments.entity(for: "panel") {
                panel.name = "billboardPanel"
                // Anchor position within the volumetric window. Default sits near the
                // bottom (close to the system window bar); taller panels can override
                // to a higher Y so their bottom edge doesn't clip against the volume floor.
                panel.position = [0, anchorY, 0]
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
                    panelScale = max(0.6, min(5.0, panelScale * Float(value.magnification)))
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
        case .phaseTwo:
            BillboardedPanel {
                ControlWindowView(screen: $screen)
                    .frame(width: 480)
                    .glassBackgroundEffect()
            }
        }
    }
}
