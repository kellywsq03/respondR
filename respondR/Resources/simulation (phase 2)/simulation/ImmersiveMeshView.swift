import QuartzCore
import RealityKit
import SwiftUI
import simd

struct ImmersiveMeshView: View {
    @Environment(AppModel.self) private var appModel
    @State private var scanner: MeshScanner?
    @State private var fireSim: FireSimulation?
    @State private var fireRenderer: FireRenderer?
    @State private var charRenderer: CharRenderer?
    @State private var fireExtinguisher: FireExtinguisherController?
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

                let sim = FireSimulation(cellSize: 0.30)
                let renderer = FireRenderer(root: root)
                let chars = CharRenderer(root: root, cellSize: 0.30) {
                    position, radius in
                    scanner.makeCharPatch(near: position, radius: radius)
                }
                self.fireSim = sim
                self.fireRenderer = renderer
                self.charRenderer = chars

                let extinguisher = FireExtinguisherController(sceneRoot: root)
                extinguisher.onStateChange = { phase, isSpraying in
                    appModel.extinguisherPhase = phase
                    appModel.isExtinguisherSpraying = isSpraying
                }
                extinguisher.onError = { message in
                    appModel.errorMessage = message
                }
                self.fireExtinguisher = extinguisher
                extinguisher.scheduleSpawn {
                    scanner.queryHeadTransform()
                }

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

                        let headTransform = scanner.queryHeadTransform()
                        extinguisher.update(deviceTransform: headTransform)
                        if let sprayCone = extinguisher.activeSprayCone {
                            sim.extinguish(in: sprayCone)
                        }
                        sim.tick(now: now)
                        let active = sim.activePositions()
                        renderer.sync(active: active)
                        chars.addCompletedBurns(sim.drainNewlyBurnt())
                        updateHUD(
                            elapsed: elapsed,
                            activeFirePositions: active,
                            headTransform: headTransform,
                            hudEntity: hudEntity
                        )
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
            charRenderer?.clear()
            appModel.resetHUD()
            appModel.startTimer()
            appModel.errorMessage = nil
            fireExtinguisher?.resetAndSchedule {
                scanner?.queryHeadTransform()
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard appModel.mode == .fire, let sim = fireSim else {
                        return
                    }
                    if fireExtinguisher?.contains(value.entity) == true {
                        fireExtinguisher?.pickUp()
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
        .simultaneousGesture(
            SpatialEventGesture()
                .onChanged { events in
                    handleSpatialEvents(events)
                }
        )
        .onDisappear {
            tickTask?.cancel()
            tickTask = nil
            fireExtinguisher?.cancel()
            fireExtinguisher = nil
            scanner?.stop()
            hudEntity = nil
            appModel.pauseTimer()
            appModel.updateHUD(deltaTime: 0, isNearActiveFire: false)
            appModel.exportHandler = nil
            appModel.immersiveSpaceOpen = false
        }
    }

    private func updateHUD(
        elapsed: TimeInterval,
        activeFirePositions: [SIMD3<Float>],
        headTransform: simd_float4x4?,
        hudEntity: Entity?
    ) {
        guard let headTransform else {
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

    private func handleSpatialEvents(_ events: SpatialEventCollection) {
        guard let fireExtinguisher else { return }

        var hasActiveExtinguisherPinch = false
        var hasFinishedEvent = false

        for event in events {
            switch event.phase {
            case .active:
                switch event.kind {
                case .directPinch, .indirectPinch:
                    if let target = event.targetedEntity,
                       fireExtinguisher.contains(target) {
                        hasActiveExtinguisherPinch = true
                    }
                default:
                    break
                }
            case .ended, .cancelled:
                hasFinishedEvent = true
            }
        }

        if hasActiveExtinguisherPinch {
            fireExtinguisher.beginSpray()
        } else if hasFinishedEvent {
            fireExtinguisher.endSpray()
        }
    }
}
