import QuartzCore
import RealityKit
import SwiftUI

struct ImmersiveMeshView: View {
    @Environment(AppModel.self) private var appModel
    @State private var scanner: MeshScanner?
    @State private var fireSim: FireSimulation?
    @State private var fireRenderer: FireRenderer?
    @State private var charRenderer: CharRenderer?
    @State private var tickTask: Task<Void, Never>?

    var body: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)

            let scanner = MeshScanner(rootEntity: root)
            scanner.mode = (appModel.mode == .fire) ? .fire : .wireframe
            scanner.setMeshVisible(appModel.meshVisible)
            self.scanner = scanner
            appModel.exportHandler = { scanner.exportRoom() }

            if appModel.mode == .fire {
                let sim = FireSimulation(cellSize: 0.05)
                let renderer = FireRenderer(root: root)
                let chars = CharRenderer(root: root, cellSize: 0.075)
                self.fireSim = sim
                self.fireRenderer = renderer
                self.charRenderer = chars
                scanner.onGeometryUpdate = { positions in
                    sim.insertGeometry(positions)
                }
                tickTask = Task { @MainActor in
                    var beat = 0
                    while !Task.isCancelled {
                        sim.tick(now: CACurrentMediaTime())
                        let active = sim.activePositions()
                        renderer.sync(active: active)
                        chars.add(sim.drainNewlyBurnt())
                        beat += 1
                        if beat % 20 == 0 {  // ~ every 2s
                            print(
                                "FireDebug: tick alive — active=\(active.count) cells=\(sim.cellCount)"
                            )
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }

            Task { await scanner.start() }
        }
        .onChange(of: appModel.meshVisible) { _, visible in
            scanner?.setMeshVisible(visible)
        }
        .onChange(of: appModel.wireframeColor) { _, color in
            scanner?.updateColor(color)
        }
        .onChange(of: appModel.resetFireTrigger) { _, _ in
            fireSim?.reset()
            fireRenderer?.clear()
            charRenderer?.clear()
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard appModel.mode == .fire, let sim = fireSim else {
                        return
                    }
                    let world = value.convert(
                        value.location3D,
                        from: .local,
                        to: .scene
                    )
                    let ignited = sim.ignite(
                        at: world,
                        now: CACurrentMediaTime()
                    )
                    print(
                        "FireDebug: TAP captured at \(world) ignited=\(ignited)"
                    )
                }
        )
        .onDisappear {
            tickTask?.cancel()
            tickTask = nil
            scanner?.stop()
            appModel.exportHandler = nil
            appModel.immersiveSpaceOpen = false
        }
    }
}
