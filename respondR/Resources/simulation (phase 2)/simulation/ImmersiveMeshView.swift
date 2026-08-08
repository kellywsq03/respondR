import SwiftUI
import RealityKit
import QuartzCore
import simd

struct ImmersiveMeshView: View {
    @Environment(AppModel.self) private var appModel
    @State private var scanner: MeshScanner?
    @State private var fireSim: FireSimulation?
    @State private var fireRenderer: FireRenderer?
    @State private var tickTask: Task<Void, Never>?
    @State private var hudEntity: Entity?

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            content.add(root)

            let scanner = MeshScanner(rootEntity: root)
            scanner.mode = (appModel.mode == .fire) ? .fire : .wireframe
            scanner.setMeshVisible(appModel.meshVisible)
            self.scanner = scanner
            appModel.exportHandler = { scanner.exportRoom() }

            if appModel.mode == .fire {
                if let hud = attachments.entity(for: "fire-hud") {
                    content.add(hud)
                    hudEntity = hud
                }

                appModel.resetHUD()
                appModel.startTimer()

                let sim = FireSimulation(cellSize: 0.15)
                let renderer = FireRenderer(root: root)
                self.fireSim = sim
                self.fireRenderer = renderer
                scanner.onGeometryUpdate = { positions in
                    sim.insertGeometry(positions)
                }
                tickTask = Task { @MainActor in
                    var beat = 0
                    var lastTick = CACurrentMediaTime()
                    while !Task.isCancelled {
                        let now = CACurrentMediaTime()
                        let elapsed = now - lastTick
                        lastTick = now

                        sim.tick(now: now)
                        let active = sim.activePositions()
                        renderer.sync(active: active)
                        updateHUD(
                            elapsed: elapsed,
                            activeFirePositions: active,
                            scanner: scanner,
                            hudEntity: hudEntity
                        )
                        beat += 1
                        if beat % 20 == 0 { // ~ every 2s
                            print("FireDebug: tick alive — active=\(active.count) cells=\(sim.cellCount)")
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }

            Task { await scanner.start() }
        } attachments: {
            if appModel.mode == .fire {
                Attachment(id: "fire-hud") {
                    HUDView()
                        .environment(appModel)
                }
            }
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
            appModel.resetHUD()
            appModel.startTimer()
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard appModel.mode == .fire, let sim = fireSim else { return }
                    let world = value.convert(value.location3D, from: .local, to: .scene)
                    let ignited = sim.ignite(at: world, now: CACurrentMediaTime())
                    print("FireDebug: TAP captured at \(world) ignited=\(ignited)")
                }
        )
        .onDisappear {
            tickTask?.cancel()
            tickTask = nil
            scanner?.stop()
            hudEntity = nil
            appModel.pauseTimer()
            appModel.updateHUD(deltaTime: 0, isNearActiveFire: false)
            appModel.exportHandler = nil
        }
    }

    private func updateHUD(
        elapsed: TimeInterval,
        activeFirePositions: [SIMD3<Float>],
        scanner: MeshScanner,
        hudEntity: Entity?
    ) {
        guard let headTransform = scanner.queryHeadTransform() else {
            appModel.updateHUD(deltaTime: elapsed, isNearActiveFire: false)
            return
        }

        let headPosition = SIMD3<Float>(
            headTransform.columns.3.x,
            headTransform.columns.3.y,
            headTransform.columns.3.z
        )
        let isNearFire = activeFirePositions.contains {
            simd_distance(headPosition, $0) < AppModel.fireProximityDistance
        }
        appModel.updateHUD(deltaTime: elapsed, isNearActiveFire: isNearFire)

        var offset = matrix_identity_float4x4
        offset.columns.3 = SIMD4<Float>(0, 0, -0.85, 1)
        hudEntity?.transform = Transform(matrix: headTransform * offset)
    }
}
