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
    @State private var presentationTask: Task<Void, Never>?
    @State private var statusEntity: Entity?
    @State private var timerEntity: Entity?
    @State private var resultEntity: Entity?
    @State private var headFollowSmoother = HeadFollowSmoother()
    @State private var pickupPinchInProgress = false

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
                if let status = attachments.entity(for: "fire-status") {
                    content.add(status)
                    statusEntity = status
                }
                if let timer = attachments.entity(for: "fire-timer") {
                    content.add(timer)
                    timerEntity = timer
                }
                if let result = attachments.entity(for: "scenario-result") {
                    result.isEnabled = false
                    content.add(result)
                    resultEntity = result
                }

                appModel.startScenarioForAvailableContent()

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
                extinguisher.preloadAsset()

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
                        let active: [SIMD3<Float>]
                        if appModel.isScenarioActive {
                            if let sprayCone = extinguisher.activeSprayCone {
                                sim.extinguish(in: sprayCone)
                            }
                            sim.tick(now: now)
                            active = sim.activePositions()
                            renderer.sync(active: active)
                            chars.addCompletedBurns(sim.drainNewlyBurnt())
                        } else {
                            extinguisher.endSpray()
                            active = sim.activePositions()
                        }
                        updateScenarioTick(
                            elapsed: elapsed,
                            activeFirePositions: active,
                            headTransform: headTransform
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

                presentationTask = Task { @MainActor in
                    var lastFrame = CACurrentMediaTime()
                    while !Task.isCancelled {
                        let now = CACurrentMediaTime()
                        let elapsed = now - lastFrame
                        lastFrame = now

                        updatePresentationVisibility(
                            statusEntity: statusEntity,
                            timerEntity: timerEntity,
                            resultEntity: resultEntity
                        )
                        if let headTransform = scanner.queryHeadTransform() {
                            let stabilizedHead = headFollowSmoother.update(
                                target: headTransform,
                                deltaTime: elapsed
                            )
                            extinguisher.update(deviceTransform: stabilizedHead)
                            updatePresentationTransforms(
                                headTransform: stabilizedHead,
                                statusEntity: statusEntity,
                                timerEntity: timerEntity,
                                resultEntity: resultEntity
                            )
                        } else {
                            extinguisher.update(deviceTransform: nil)
                        }

                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
            }

            Task { await scanner.start() }
        } attachments: {
            if appModel.mode == .fire {
                Attachment(id: "fire-status") {
                    HUDStatusView()
                        .environment(appModel)
                }
                Attachment(id: "fire-timer") {
                    HUDTimerView()
                        .environment(appModel)
                }
                Attachment(id: "scenario-result") {
                    ScenarioResultView()
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
            appModel.errorMessage = nil
            appModel.startScenarioForAvailableContent()
            pickupPinchInProgress = false
            headFollowSmoother.reset()
            fireExtinguisher?.resetForAwaitingFireStart()
            if appModel.isScenarioActive {
                fireExtinguisher?.preloadAsset()
            }
        }
        .onChange(of: appModel.scenarioPhase) { _, phase in
            if phase != .active {
                pickupPinchInProgress = false
                fireExtinguisher?.resetForAwaitingFireStart()
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard appModel.mode == .fire,
                          appModel.isScenarioActive,
                          let sim = fireSim
                    else {
                        return
                    }
                    if fireExtinguisher?.contains(value.entity) == true {
                        return
                    }
                    guard appModel.fireStartPhase == .awaitingFireStart else { return }
                    guard let headTransform = scanner?.queryHeadTransform() else {
                        appModel.errorMessage =
                            "Head tracking is unavailable. Look around, then pinch again."
                        return
                    }

                    let headPosition = SIMD3<Float>(
                        headTransform.columns.3.x,
                        headTransform.columns.3.y,
                        headTransform.columns.3.z
                    )
                    let startedFires = sim.igniteRandomFires(
                        around: headPosition,
                        count: 5,
                        now: CACurrentMediaTime()
                    )
                    guard startedFires.count == 5 else {
                        appModel.errorMessage =
                            "Look around to scan more surfaces, then pinch again."
                        return
                    }
                    guard appModel.recordFireStarted() else { return }

                    appModel.errorMessage = nil
                    appModel.statusMessage = "Five fires started."
                    fireExtinguisher?.scheduleSpawn {
                        scanner?.queryHeadTransform()
                    }
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
            presentationTask?.cancel()
            presentationTask = nil
            fireExtinguisher?.cancel()
            fireExtinguisher = nil
            scanner?.stop()
            statusEntity = nil
            timerEntity = nil
            resultEntity = nil
            pickupPinchInProgress = false
            headFollowSmoother.reset()
            appModel.stopScenario()
            appModel.exportHandler = nil
            appModel.immersiveSpaceOpen = false
        }
    }

    private func updateScenarioTick(
        elapsed: TimeInterval,
        activeFirePositions: [SIMD3<Float>],
        headTransform: simd_float4x4?
    ) {
        guard let headTransform else {
            appModel.updateScenario(deltaTime: elapsed, isNearActiveFire: false)
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
        appModel.updateScenario(deltaTime: elapsed, isNearActiveFire: isNearFire)
    }

    private func updatePresentationVisibility(
        statusEntity: Entity?,
        timerEntity: Entity?,
        resultEntity: Entity?
    ) {
        let showsResult = appModel.scenarioOutcome != nil
        statusEntity?.isEnabled = !showsResult
        timerEntity?.isEnabled = !showsResult
        resultEntity?.isEnabled = showsResult
    }

    private func updatePresentationTransforms(
        headTransform: simd_float4x4,
        statusEntity: Entity?,
        timerEntity: Entity?,
        resultEntity: Entity?
    ) {
        statusEntity?.transform = Transform(
            matrix: headTransform * translation(x: -0.45, y: 0.25, z: -1.15)
        )
        timerEntity?.transform = Transform(
            matrix: headTransform * translation(x: 0.45, y: 0.25, z: -1.15)
        )
        resultEntity?.transform = Transform(
            matrix: headTransform * translation(x: 0, y: 0, z: -0.95)
        )
    }

    private func handleSpatialEvents(_ events: SpatialEventCollection) {
        guard appModel.isScenarioActive, let fireExtinguisher else { return }

        var hasFinishedEvent = false

        for event in events {
            switch event.phase {
            case .active:
                switch event.kind {
                case .directPinch, .indirectPinch:
                    if let target = event.targetedEntity,
                       fireExtinguisher.contains(target) {
                        switch fireExtinguisher.phase {
                        case .available:
                            if fireExtinguisher.pickUp() {
                                pickupPinchInProgress = true
                            }
                        case .equipped where !pickupPinchInProgress:
                            _ = fireExtinguisher.beginSpray()
                        case .waitingToSpawn, .equipped:
                            break
                        }
                    }
                default:
                    break
                }
            case .ended, .cancelled:
                hasFinishedEvent = true
            @unknown default:
                hasFinishedEvent = true
            }
        }

        if hasFinishedEvent {
            fireExtinguisher.endSpray()
            pickupPinchInProgress = false
        }
    }

    private func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }
}
