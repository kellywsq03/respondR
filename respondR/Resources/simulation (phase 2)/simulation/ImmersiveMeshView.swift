import QuartzCore
import RealityKit
import SwiftUI
import simd

struct ImmersiveMeshView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var scanner: MeshScanner?
    @State private var fireSim: FireSimulation?
    @State private var fireRenderer: FireRenderer?
    @State private var charRenderer: CharRenderer?
    @State private var fireExtinguisher: FireExtinguisherController?
    @State private var casualtyController: CasualtyController?
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

                let casualty = CasualtyController(sceneRoot: root)
                casualty.onError = { message in
                    appModel.errorMessage = message
                }
                casualty.onWaitingForFloor = {
                    guard appModel.isScenarioActive else { return }
                    appModel.statusMessage =
                        "Look around to scan more floor so casualty Gabe can appear."
                }
                casualty.onDidSpawn = {
                    guard appModel.isScenarioActive else { return }
                    appModel.statusMessage =
                        "Casualty Gabe appeared. Look at him and pinch once to rescue him."
                }
                self.casualtyController = casualty
                casualty.preloadAsset()

                let extinguisher = FireExtinguisherController(sceneRoot: root)
                extinguisher.onStateChange = { phase, isSpraying in
                    appModel.extinguisherPhase = phase
                    appModel.isExtinguisherSpraying = isSpraying
                }
                extinguisher.onError = { message in
                    appModel.errorMessage = message
                }
                extinguisher.onDidSpawn = {
                    guard appModel.isScenarioActive else { return }
                    casualty.scheduleSpawn(
                        deviceTransform: { scanner.queryHeadTransform() },
                        floorPosition: { headPosition in
                            scanner.randomFloorPosition(
                                around: headPosition,
                                horizontalDistance: 6.5...7.5,
                                verticalOffset: -2.3 ... -0.5
                            )
                        }
                    )
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
                            let visuals = sim.activeVisuals(now: now)
                            active = visuals.map(\.position)
                            renderer.sync(active: visuals)
                            chars.addCompletedBurns(sim.drainNewlyBurnt())
                        } else {
                            extinguisher.endSpray()
                            active = sim.activeVisuals(now: now).map(\.position)
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
                            casualty.update(deviceTransform: stabilizedHead)
                            updatePresentationTransforms(
                                headTransform: stabilizedHead,
                                statusEntity: statusEntity,
                                timerEntity: timerEntity,
                                resultEntity: resultEntity
                            )
                        } else {
                            extinguisher.update(deviceTransform: nil)
                            casualty.update(deviceTransform: nil)
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
            casualtyController?.resetForAwaitingSpawn()
            if appModel.isScenarioActive {
                fireExtinguisher?.preloadAsset()
                casualtyController?.preloadAsset()
            }
        }
        .onChange(of: appModel.scenarioPhase) { _, phase in
            if phase != .active {
                pickupPinchInProgress = false
                fireExtinguisher?.resetForAwaitingFireStart()
                casualtyController?.resetForAwaitingSpawn()
            }
        }
        .onChange(of: appModel.endTrainingTrigger) { _, _ in
            Task {
                await dismissImmersiveSpace()
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
                    if casualtyController?.contains(value.entity) == true
                        || fireExtinguisher?.contains(value.entity) == true {
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
            casualtyController?.cancel()
            casualtyController = nil
            scanner?.stop()
            statusEntity = nil
            timerEntity = nil
            resultEntity = nil
            pickupPinchInProgress = false
            headFollowSmoother.reset()
            appModel.stopScenario()
            appModel.exportHandler = nil
            appModel.immersiveSpaceOpen = false
            openWindow(id: AppSceneID.mainWindow)
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
            matrix: headTransform * translation(x: -0.45, y: 0.20, z: -1.15)
        )
        timerEntity?.transform = Transform(
            matrix: headTransform * translation(x: 0, y: 0.225, z: -1.15)
        )
        resultEntity?.transform = Transform(
            matrix: headTransform * translation(x: 0, y: 0, z: -0.95)
        )
    }

    private func handleSpatialEvents(_ events: SpatialEventCollection) {
        guard appModel.isScenarioActive else { return }

        var hasFinishedEvent = false

        for event in events {
            switch event.phase {
            case .active:
                switch event.kind {
                case .directPinch, .indirectPinch:
                    guard let target = event.targetedEntity else { continue }

                    if let casualtyController,
                       casualtyController.contains(target) {
                        if appModel.recordCasualtyRescue(
                            casualtyID: AppModel.maplessCasualtyID
                        ), casualtyController.completeRescue() {
                            appModel.statusMessage =
                                "Gabe rescued. Carry him to the exit."
                        }
                        continue
                    }

                    if let fireExtinguisher,
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
            fireExtinguisher?.endSpray()
            pickupPinchInProgress = false
        }
    }

    private func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }
}
