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
    @State private var exitBeaconEntity: Entity?
    @State private var exitLabelEntity: Entity?
    @State private var actionPromptEntity: Entity?
    @State private var gazeCatcherEntity: Entity?
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
                if let prompt = attachments.entity(for: "action-prompt") {
                    prompt.isEnabled = false
                    content.add(prompt)
                    actionPromptEntity = prompt
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

                // An indirect (gaze + pinch) event is only delivered to the app
                // when the gaze has an input target. Without this, pinching
                // while looking at open room delivers nothing and the spray
                // never starts. This invisible plane rides far in front of the
                // learner so the gaze ALWAYS lands on something; everything
                // real is nearer, so it never steals a deliberate target.
                let catcher = Entity()
                catcher.name = "gaze-catcher"
                catcher.components.set(
                    CollisionComponent(
                        shapes: [ShapeResource.generateBox(width: 80, height: 80, depth: 0.1)]
                    )
                )
                catcher.components.set(InputTargetComponent())
                content.add(catcher)
                gazeCatcherEntity = catcher

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
                                        // Victim spawns 4.5-7 m away — far enough
                                        // to walk to, near enough to stay		 inside
                                        // the current room. If no such floor has
                                        // been scanned after ~7 s, relax the
                                        // minimum so Gabe still appears.
                                        var casualtyAttempts = 0
                                        casualty.scheduleSpawn(
                                            deviceTransform: { scanner.queryHeadTransform() },
                                            floorPosition: { head in
                                                casualtyAttempts += 1
                                                let minimumDistance: Float =
                                                    casualtyAttempts > 30 ? 1.5 : 4.5
                                                return scanner.randomFloorPosition(
                                                    around: head,
                                                    horizontalDistance: minimumDistance...7,
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

                        // Drive the head-locked action prompt. Written only on
                        // change so the SwiftUI attachment isn't rebuilt every
                        // tick.
                        let nextPrompt: AppModel.ActionPrompt?
                        if !appModel.isScenarioActive {
                            nextPrompt = nil
                        } else if let bottle = extinguisher.availableWorldPosition,
                                  let headTransform {
                            let head = SIMD3<Float>(
                                headTransform.columns.3.x,
                                headTransform.columns.3.y,
                                headTransform.columns.3.z
                            )
                            let metres = simd_distance(
                                SIMD2<Float>(head.x, head.z),
                                SIMD2<Float>(bottle.x, bottle.z)
                            )
                            nextPrompt = .pickUpExtinguisher(
                                inRange: metres <= FireExtinguisherController.pickUpDistance,
                                metres: (metres * 10).rounded() / 10
                            )
                        } else if let victim = casualty.availableWorldPosition,
                                  let headTransform {
                            let head = SIMD3<Float>(
                                headTransform.columns.3.x,
                                headTransform.columns.3.y,
                                headTransform.columns.3.z
                            )
                            let metres = simd_distance(
                                SIMD2<Float>(head.x, head.z),
                                SIMD2<Float>(victim.x, victim.z)
                            )
                            nextPrompt = .rescueVictim(
                                inRange: metres <= AppModel.victimRescueDistance,
                                metres: (metres * 10).rounded() / 10
                            )
                        } else {
                            nextPrompt = nil
                        }
                        if appModel.actionPrompt != nextPrompt {
                            appModel.actionPrompt = nextPrompt
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

                        // Passive "RETURN HERE" sign over the start beacon.
                        // Writes are guarded: rewriting an entity's transform
                        // every frame is what made gaze targeting glitch.
                        let labelHead = scanner.queryHeadTransform()
                        if let beacon = exitBeaconEntity, beacon.isEnabled {
                            // Passive text — no hit-testing, safe to scale.
                            positionLabel(
                                exitLabelEntity,
                                at: beacon.position + SIMD3<Float>(0, 2.55, 0),
                                headTransform: labelHead)
                        } else if exitLabelEntity?.isEnabled == true {
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
                Attachment(id: "action-prompt") {
                    // Head-locked, always directly in front of the learner with
                    // nothing between it and their eyes: the same mechanism as
                    // the status HUD and the control window, both of which
                    // target reliably. This is the guaranteed pickup path.
                    Group {
                        switch appModel.actionPrompt {
                        case .pickUpExtinguisher(let inRange, let metres):
                            Button {
                                pickUpExtinguisher()
                            } label: {
                                Label(
                                    inRange
                                        ? "Pick Up Extinguisher"
                                        : "Walk to the Extinguisher (\(String(format: "%.1f", metres)) m)",
                                    systemImage: inRange ? "flame.circle.fill" : "figure.walk"
                                )
                                .font(.system(size: 34, weight: .bold))
                                .padding(.horizontal, 26)
                                .padding(.vertical, 16)
                            }
                            .tint(.teal)
                            .buttonStyle(.borderedProminent)
                            .disabled(!inRange)
                        case .rescueVictim(let inRange, let metres):
                            Button {
                                rescueVictim()
                            } label: {
                                Label(
                                    inRange
                                        ? "Rescue Victim"
                                        : "Move Closer to Victim (\(String(format: "%.1f", metres)) m)",
                                    systemImage: inRange ? "figure.arms.open" : "figure.walk"
                                )
                                .font(.system(size: 34, weight: .bold))
                                .padding(.horizontal, 26)
                                .padding(.vertical, 16)
                            }
                            .tint(.red)
                            .buttonStyle(.borderedProminent)
                            .disabled(!inRange)
                        case nil:
                            EmptyView()
                        }
                    }
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
            exitBeaconEntity = nil
            exitLabelEntity = nil
            actionPromptEntity = nil
            gazeCatcherEntity = nil
            appModel.actionPrompt = nil
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
        let showsPrompt = !showsResult && appModel.actionPrompt != nil
        if actionPromptEntity?.isEnabled != showsPrompt {
            actionPromptEntity?.isEnabled = showsPrompt
        }
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
        // Lower centre, clear of the status/timer row and of the held
        // extinguisher (which sits to the lower right).
        actionPromptEntity?.transform = Transform(
            matrix: headTransform * translation(x: -0.10, y: -0.20, z: -1.00)
        )
        // Far enough away that every real target wins the gaze first.
        gazeCatcherEntity?.transform = Transform(
            matrix: headTransform * translation(x: 0, y: 0, z: -9)
        )
    }

    /// Moves/scales a floating label only when the change is meaningful.
    /// Static items therefore get ZERO per-frame writes — continuous transform
    /// updates under the gaze are what made targeting the labels glitchy.
    private func positionLabel(
        _ label: Entity?,
        at target: SIMD3<Float>,
        headTransform: simd_float4x4?,
        dynamicScale: Bool = true
    ) {
        guard let label else { return }
        if simd_distance(label.position, target) > 0.03 {
            label.position = target
        }
        // Interactive attachments must NOT be entity-scaled: the system's
        // hover/pinch hit region does not follow entity scale, leaving a big
        // visual with a tiny hit box. Buttons pass dynamicScale: false and get
        // their size in SwiftUI points instead. Passive labels scale with
        // distance (20% hysteresis so walking doesn't retrigger writes).
        var desired: Float = 1
        if dynamicScale, let headTransform {
            let head = SIMD3<Float>(
                headTransform.columns.3.x,
                headTransform.columns.3.y,
                headTransform.columns.3.z
            )
            desired = max(1.0, min(6.0, simd_distance(target, head) * 0.5))
        }
        if abs(label.scale.x - desired) > desired * 0.2 {
            label.scale = SIMD3<Float>(repeating: desired)
        }
        if !label.isEnabled {
            label.isEnabled = true
        }
    }

    /// Whether `entity` is `ancestor` or one of its descendants.
    private static func isPart(_ entity: Entity, of ancestor: Entity?) -> Bool {
        guard let ancestor else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if candidate === ancestor { return true }
            current = candidate.parent
        }
        return false
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
              fireExtinguisher.phase == .available,
              // Must be standing beside it, whichever path triggered the pickup.
              appModel.actionPrompt?.isInRange == true else { return }
        if fireExtinguisher.pickUp() {
            appModel.statusMessage =
                "Extinguisher equipped — pinch and hold anywhere to spray."
        }
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

        // Decide from the whole collection rather than per event: a delivery
        // can carry an active pinch from one hand and an ended one from the
        // other, and the old per-event handling then began and immediately
        // ended the spray in the same call.
        var heldPinches = 0
        var rescuePinch = false

        for event in events {
            guard event.kind == .directPinch || event.kind == .indirectPinch else { continue }
            switch event.phase {
            case .active:
                // A pinch aimed at the victim is a rescue, never a spray —
                // even while the extinguisher is equipped.
                if let target = event.targetedEntity,
                   let casualtyController,
                   casualtyController.contains(target) {
                    rescuePinch = true
                    continue
                }
                // A pinch on the passive exit sign isn't a spray trigger.
                if let target = event.targetedEntity,
                   Self.isPart(target, of: exitLabelEntity) {
                    continue
                }
                heldPinches += 1
            default:
                break
            }
        }

        if rescuePinch {
            rescueVictim()
        }

        if heldPinches > 0 {
            if fireExtinguisher.phase == .equipped {
                _ = fireExtinguisher.beginSpray()
            }
        } else {
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
