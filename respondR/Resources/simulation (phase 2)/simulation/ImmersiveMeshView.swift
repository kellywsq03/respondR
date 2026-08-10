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
    @State private var victimLabelEntity: Entity?
    @State private var extinguisherLabelEntity: Entity?
    @State private var exitBeaconEntity: Entity?
    @State private var exitLabelEntity: Entity?
    @State private var headFollowSmoother = HeadFollowSmoother()

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            content.add(root)

            let scanner = MeshScanner(rootEntity: root)
            scanner.mode = (appModel.mode == .fire) ? .fire : .wireframe
            scanner.setMeshVisible(appModel.meshVisible)
            self.scanner = scanner
            appModel.exportHandler = { scanner.exportRoom() }

            // The fire grid lives in both modes: wireframe sweeps fill it for
            // room-map authoring, fire mode burns it. A saved map re-seeds it
            // once ARKit relocalises the persisted room anchor, so fires can
            // start anywhere in the mapped room without re-scanning.
            // spreadInterval well under burnDuration so one seed fire GROWS
            // quickly (a new neighbour every 3 s per cell, capped at maxActive)
            // while char only forms when a cell burns out at 45 s.
            let sim = FireSimulation(cellSize: 0.30, burnDuration: 45, spreadInterval: 3)
            self.fireSim = sim
            scanner.onGeometryUpdate = { positions in
                sim.insertGeometry(positions)
            }
            configureRoomMap(scanner: scanner, sim: sim)

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
                if let victimLabel = attachments.entity(for: "victim-label") {
                    victimLabel.components.set(BillboardComponent())
                    victimLabel.isEnabled = false
                    content.add(victimLabel)
                    victimLabelEntity = victimLabel
                }
                if let extinguisherLabel = attachments.entity(for: "extinguisher-label") {
                    extinguisherLabel.components.set(BillboardComponent())
                    extinguisherLabel.isEnabled = false
                    content.add(extinguisherLabel)
                    extinguisherLabelEntity = extinguisherLabel
                }
                if let exitLabel = attachments.entity(for: "exit-label") {
                    exitLabel.components.set(BillboardComponent())
                    exitLabel.isEnabled = false
                    content.add(exitLabel)
                    exitLabelEntity = exitLabel
                }
                let beacon = Self.makeExitBeacon()
                beacon.isEnabled = false
                root.addChild(beacon)
                exitBeaconEntity = beacon

                appModel.startScenarioForAvailableContent()

                let renderer = FireRenderer(root: root)
                let chars = CharRenderer(root: root, cellSize: 0.30) {
                    position, radius in
                    scanner.makeCharPatch(near: position, radius: radius)
                }
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
                    appModel.statusMessage =
                        "Fire extinguisher nearby — look at it and pinch once to pick it up."
                }
                self.fireExtinguisher = extinguisher
                extinguisher.preloadAsset()

                tickTask = Task { @MainActor in
                    var beat = 0
                    var lastTick = CACurrentMediaTime()
                    // Scenario orchestration state, reset with the scenario.
                    var breakoutDeadline: TimeInterval?
                    var startPosition: SIMD3<Float>?
                    var lastResetCount = appModel.resetFireTrigger
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

                        // --- Scenario orchestration: breakout, start point, exit ---
                        if appModel.resetFireTrigger != lastResetCount {
                            lastResetCount = appModel.resetFireTrigger
                            breakoutDeadline = nil
                            startPosition = nil
                        }
                        if !appModel.isScenarioActive {
                            exitBeaconEntity?.isEnabled = false
                        } else if let headTransform {
                            let headPosition = SIMD3<Float>(
                                headTransform.columns.3.x,
                                headTransform.columns.3.y,
                                headTransform.columns.3.z
                            )
                            // The learner's position when the scenario began is
                            // the "exit" they must return to for a rescue win.
                            if startPosition == nil { startPosition = headPosition }

                            if appModel.fireStartPhase == .awaitingFireStart {
                                let roomKnown = appModel.roomMapRestored || sim.cellCount > 300
                                if roomKnown, breakoutDeadline == nil {
                                    breakoutDeadline = now + Double.random(in: 4...10)
                                } else if let deadline = breakoutDeadline, now >= deadline {
                                    // One fire, far from the learner; fall back
                                    // to a nearer ring only if the room offers
                                    // nothing beyond 4 m.
                                    var started = sim.igniteRandomFires(
                                        around: headPosition,
                                        count: 1,
                                        now: now,
                                        horizontalDistance: 4.0...30.0
                                    )
                                    if started.isEmpty {
                                        started = sim.igniteRandomFires(
                                            around: headPosition,
                                            count: 1,
                                            now: now,
                                            horizontalDistance: 2.0...30.0
                                        )
                                    }
                                    if started.isEmpty {
                                        breakoutDeadline = now + 2  // grid still sparse; retry
                                    } else {
                                        _ = appModel.recordFireStarted()
                                        appModel.statusMessage =
                                            "A fire has broken out! Help is on the way — watch for the extinguisher and the victim."
                                        extinguisher.scheduleSpawn {
                                            scanner.queryHeadTransform()
                                        }
                                        // Victim spawns far too; if no far floor
                                        // has been scanned after ~7 s of polling,
                                        // relax the minimum so Gabe still appears.
                                        var casualtyAttempts = 0
                                        casualty.scheduleSpawn(
                                            deviceTransform: { scanner.queryHeadTransform() },
                                            floorPosition: { head in
                                                casualtyAttempts += 1
                                                let minimumDistance: Float =
                                                    casualtyAttempts > 30 ? 2.0 : 4.0
                                                return scanner.randomFloorPosition(
                                                    around: head,
                                                    horizontalDistance: minimumDistance...12.0,
                                                    verticalOffset: -2.3 ... -0.5
                                                )
                                            }
                                        )
                                    }
                                }
                            }

                            // Rescued: show the start beacon; arriving completes it.
                            if appModel.remainingCasualties == 0,
                               appModel.rescuedCasualties > 0,
                               let start = startPosition {
                                exitBeaconEntity?.position = SIMD3<Float>(
                                    start.x, start.y - 1.5, start.z)
                                exitBeaconEntity?.isEnabled = true
                                let horizontal = simd_length(
                                    SIMD2<Float>(
                                        headPosition.x - start.x,
                                        headPosition.z - start.z))
                                if horizontal < 1.0 {
                                    exitBeaconEntity?.isEnabled = false
                                    appModel.recordExitReached()
                                }
                            }
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

                        // Floating pointer labels over the spawned victim and
                        // extinguisher (billboarded; hidden once picked up).
                        // Attachments render at a fixed point scale, so at room
                        // distance they'd be centimetres tall — scale them with
                        // distance to stay readable and easy to pinch.
                        let labelScale: (SIMD3<Float>) -> SIMD3<Float> = { position in
                            guard let head = scanner.queryHeadTransform() else {
                                return SIMD3<Float>(repeating: 2)
                            }
                            let headPosition = SIMD3<Float>(
                                head.columns.3.x, head.columns.3.y, head.columns.3.z)
                            let distance = simd_distance(position, headPosition)
                            return SIMD3<Float>(repeating: max(1.0, min(6.0, distance * 0.5)))
                        }
                        if let position = casualty.availableWorldPosition {
                            victimLabelEntity?.position = position + SIMD3<Float>(0, 0.95, 0)
                            victimLabelEntity?.scale = labelScale(position)
                            victimLabelEntity?.isEnabled = true
                        } else {
                            victimLabelEntity?.isEnabled = false
                        }
                        if let position = extinguisher.availableWorldPosition {
                            extinguisherLabelEntity?.position = position + SIMD3<Float>(0, 0.5, 0)
                            extinguisherLabelEntity?.scale = labelScale(position)
                            extinguisherLabelEntity?.isEnabled = true
                        } else {
                            extinguisherLabelEntity?.isEnabled = false
                        }
                        if let beacon = exitBeaconEntity, beacon.isEnabled {
                            let position = beacon.position + SIMD3<Float>(0, 2.55, 0)
                            exitLabelEntity?.position = position
                            exitLabelEntity?.scale = labelScale(position)
                            exitLabelEntity?.isEnabled = true
                        } else {
                            exitLabelEntity?.isEnabled = false
                        }
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
                Attachment(id: "victim-label") {
                    // A real SwiftUI Button: pickup rides on the same native
                    // gaze+pinch mechanism as the control-window buttons, which
                    // is far more reliable than RealityKit collision targeting.
                    Button {
                        rescueVictim()
                    } label: {
                        VStack(spacing: 4) {
                            Text("VICTIM")
                                .font(.title.bold())
                            Text("Pinch to rescue")
                                .font(.headline)
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.title2)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                }
                Attachment(id: "extinguisher-label") {
                    Button {
                        pickUpExtinguisher()
                    } label: {
                        VStack(spacing: 4) {
                            Text("EXTINGUISHER")
                                .font(.title.bold())
                            Text("Pinch to pick up")
                                .font(.headline)
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.title2)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                    .tint(.teal)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                }
                Attachment(id: "exit-label") {
                    VStack(spacing: 2) {
                        Text("RETURN HERE")
                            .font(.headline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.green.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
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
            // Pickup and rescue ride on the targeted tap gesture — the same
            // mechanism the surface-pinch used, which targets entities far more
            // reliably than inspecting SpatialEventGesture's targetedEntity.
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handlePickupTap(value.entity)
                }
        )
        .simultaneousGesture(
            SpatialEventGesture()
                .onChanged { events in
                    handleSpatialEvents(events)
                }
                .onEnded { _ in
                    // Guaranteed terminal callback. Relying on .onChanged alone
                    // left the spray stuck on: releasing the pinch while the
                    // gaze targets nothing (unmeshed air) never delivered the
                    // .ended event to the handler above.
                    fireExtinguisher?.endSpray()
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
            victimLabelEntity = nil
            extinguisherLabelEntity = nil
            exitBeaconEntity = nil
            exitLabelEntity = nil
            headFollowSmoother.reset()
            appModel.stopScenario()
            appModel.exportHandler = nil
            appModel.saveRoomMapHandler = nil
            appModel.deleteRoomMapHandler = nil
            appModel.roomMapRestored = false
            appModel.immersiveSpaceOpen = false
            openWindow(id: AppSceneID.mainWindow)
        }
    }

    /// Wires the persistent room map: restores a saved map into the fire grid
    /// once its world anchor is relocalised, and installs the save/delete
    /// handlers the control window calls.
    private func configureRoomMap(scanner: MeshScanner, sim: FireSimulation) {
        if let map = RoomMapStore.load() {
            scanner.roomAnchorIDToResolve = map.anchorID
            scanner.onRoomAnchorResolved = { transform in
                // Anchor updates repeat as tracking refines; seed only once.
                guard !appModel.roomMapRestored else { return }
                appModel.roomMapRestored = true
                sim.insertGeometry(map.worldPositions(originFromAnchor: transform))
                appModel.statusMessage =
                    "Room map restored (\(map.cellCount) surfaces). Fires can start anywhere in the room."
            }
        }

        appModel.saveRoomMapHandler = {
            guard let head = scanner.queryHeadTransform() else {
                return "Head tracking unavailable — look around, then try again."
            }
            let cells = sim.occupiedCellCenters
            guard cells.count >= 100 else {
                return "Only \(cells.count) surface cells captured — sweep more of the room first."
            }
            if let previous = RoomMapStore.load() {
                await scanner.removeRoomAnchor(id: previous.anchorID)
            }
            do {
                let anchorID = try await scanner.addRoomAnchor(at: head)
                let map = RoomMap(
                    anchorID: anchorID,
                    cellSize: sim.gridCellSize,
                    originFromAnchor: head,
                    worldCells: cells
                )
                try RoomMapStore.save(map)
                appModel.roomMapSurfaceCount = map.cellCount
                appModel.roomMapRestored = true  // this session's grid is the map
                return "Room map saved (\(map.cellCount) surfaces)."
            } catch {
                return "Couldn't save the room map: \(error.localizedDescription)"
            }
        }

        appModel.deleteRoomMapHandler = {
            if let previous = RoomMapStore.load() {
                await scanner.removeRoomAnchor(id: previous.anchorID)
            }
            RoomMapStore.delete()
            scanner.roomAnchorIDToResolve = nil
            appModel.roomMapSurfaceCount = nil
            appModel.roomMapRestored = false
            return "Room map deleted."
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

    /// Rescues the victim: shared by the label button and model taps.
    private func rescueVictim() {
        guard appModel.isScenarioActive, let casualtyController else { return }
        if appModel.recordCasualtyRescue(casualtyID: AppModel.maplessCasualtyID),
           casualtyController.completeRescue() {
            appModel.statusMessage =
                "Victim rescued. Return to the green beacon at your starting point."
        }
    }

    /// Picks up the extinguisher: shared by the label button and model taps.
    private func pickUpExtinguisher() {
        guard appModel.isScenarioActive,
              let fireExtinguisher,
              fireExtinguisher.phase == .available else { return }
        _ = fireExtinguisher.pickUp()
    }

    /// One look-and-pinch on the models themselves (secondary path — the big
    /// label buttons above them are the primary, most reliable target).
    private func handlePickupTap(_ entity: Entity) {
        guard appModel.mode == .fire, appModel.isScenarioActive else { return }

        if let casualtyController, casualtyController.contains(entity) {
            rescueVictim()
            return
        }

        if let fireExtinguisher, fireExtinguisher.contains(entity) {
            pickUpExtinguisher()
        }
    }

    /// Pinch-and-hold anywhere sprays while the extinguisher is equipped.
    /// (Requiring the gaze to stay on the held bottle made spraying unreliable:
    /// the learner looks at the fire, not at the bottle in their hand.)
    private func handleSpatialEvents(_ events: SpatialEventCollection) {
        guard appModel.isScenarioActive, let fireExtinguisher else { return }

        var hasFinishedEvent = false

        for event in events {
            switch event.phase {
            case .active:
                switch event.kind {
                case .directPinch, .indirectPinch:
                    // A pinch aimed at the victim is a rescue, never a spray —
                    // even while the extinguisher is equipped.
                    if let target = event.targetedEntity,
                       let casualtyController,
                       casualtyController.contains(target) {
                        rescueVictim()
                        continue
                    }
                    if fireExtinguisher.phase == .equipped {
                        _ = fireExtinguisher.beginSpray()
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
        }
    }

    private func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }

    /// Green floor ring + light beam marking the learner's starting point.
    /// Shown after the rescue; walking into it completes the scenario.
    private static func makeExitBeacon() -> Entity {
        let container = Entity()
        container.name = "exit-start-beacon"
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: 0.45),
            materials: [UnlitMaterial(color: UIColor.systemGreen.withAlphaComponent(0.8))]
        )
        container.addChild(ring)
        let beam = ModelEntity(
            mesh: .generateCylinder(height: 2.4, radius: 0.035),
            materials: [UnlitMaterial(color: UIColor.systemGreen.withAlphaComponent(0.35))]
        )
        beam.position.y = 1.2
        container.addChild(beam)
        return container
    }
}
