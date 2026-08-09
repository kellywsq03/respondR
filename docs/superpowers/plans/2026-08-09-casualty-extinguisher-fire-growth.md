# Phase 2 Casualty, Extinguisher Reliability, and Fire Growth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one delayed rescuable Gabe casualty, improve extinguisher targeting and nozzle-aligned spray visibility, grow fires to 4x before natural char, and hide the empty main volume during immersion.

**Architecture:** Add a focused `CasualtyController`, extend `MeshScanner` with floor-aware mapless placement, and keep `ImmersiveMeshView` as the lifecycle/gesture coordinator. Keep extinguisher-specific interaction geometry inside `FireExtinguisherController`, expose age-scaled visual samples from `FireSimulation`, and use explicit window scene lifecycle for the single existing main window.

**Tech Stack:** Swift 6, SwiftUI, RealityKit, ARKit Scene Reconstruction and World Tracking, visionOS 27 SDK, Xcode 27 beta.

## Global Constraints

- Work on the existing `fire-simulator` branch.
- Use `gabe.usdz` as the single casualty with ID `mapless-gabe`.
- Start the casualty's fixed five-second delay only after the extinguisher is actually installed.
- Place world Gabe on scanned floor 6.5–7.5 metres from the current head position; do not add a floating fallback.
- Rescue with one direct or indirect gaze-targeted pinch; world Gabe disappears immediately and carried Gabe is uniform scale 0.2 in the lower-left view.
- Expand extinguisher pickup targeting to twice the normalized model bounds.
- Render an unlit, double-sided white cone from the black hose nozzle without powder particles.
- Grow naturally burning fire from 1x to approximately 4x; only natural burnout creates char.
- Keep Release blocked in Preparing until the real anchor map is supplied.
- Preserve the fixed five-minute timer, rescue/exit victory rules, lower-right extinguisher, upper-left status, upper-right timer, hiss, and no-char extinguishing behavior.
- Preserve the existing Phase 1 volumetric main window; dismiss it only while immersion is open.
- Do not add automated scenario tests. Validate with strict builds, Xcode analysis, source checks, and physical Vision Pro acceptance gates.

---

### Task 1: Expose stable age-scaled fire visuals

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/FireRenderer.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift`

**Interfaces:**

- Produces: `FireVisualSample { position: SIMD3<Float>, scale: Float }`.
- Produces: `FireSimulation.activeVisuals(now:) -> [FireVisualSample]` in stable coordinate order.
- Consumes: `FireRenderer.sync(active: [FireVisualSample])`.

- [ ] **Step 1: Add fire timing and visual sample data**

Add a top-level value type and retain the current phase start in runtime:

```swift
struct FireVisualSample {
    let position: SIMD3<Float>
    let scale: Float
}

private struct Runtime {
    var state: CellState
    var phaseStart: TimeInterval
    var phaseEnd: TimeInterval
    var nextSpread: TimeInterval
}
```

Set `phaseStart = now` in `igniteCell`. When ignition becomes burning, reset `phaseStart = now` and retain the existing `phaseEnd = now + burnDuration`.

- [ ] **Step 2: Return stable visual growth samples**

Implement `activeVisuals(now:)` by sorting runtime coordinates lexicographically by X, then Y, then Z. Igniting scale is `1`. Burning scale is:

```swift
let elapsed = max(0, now - runtime.phaseStart)
let progress = min(1, Float(elapsed / burnDuration))
let scale = 1 + 3 * progress
```

Do not alter active membership, spread, extinguished cells, pending char, or damage positions.

- [ ] **Step 3: Apply visual scale in the renderer**

Change the pool sync signature and set both position and uniform scale:

```swift
func sync(active visuals: [FireVisualSample]) {
    for (index, entity) in pool.enumerated() {
        if index < visuals.count {
            let visual = visuals[index]
            entity.position = visual.position
            entity.scale = SIMD3<Float>(repeating: visual.scale)
            entity.isEnabled = true
        } else {
            entity.isEnabled = false
            entity.scale = SIMD3<Float>(repeating: 1)
        }
    }
}
```

- [ ] **Step 4: Feed samples from the 10 Hz tick**

In `ImmersiveMeshView`, call `sim.activeVisuals(now: now)`, sync the renderer, and derive `activeFirePositions` from those samples for proximity damage.

- [ ] **Step 5: Run strict Debug simulator build**

```bash
DEVELOPER_DIR=/Users/kc/Downloads/Xcode-beta.app/Contents/Developer xcodebuild -quiet -project respondR.xcodeproj -scheme respondR -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/respondR-fire-growth CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Expected: exit code 0.

- [ ] **Step 6: Commit fire growth**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/FireRenderer.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift'
git commit -m 'feat: grow active fires over their lifetime'
```

---

### Task 2: Expand extinguisher targeting and anchor spray to the hose

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherController.swift`

**Interfaces:**

- Produces: `var onDidSpawn: (() -> Void)?` called after successful installation.
- Keeps: `contains(_:)`, `pickUp()`, `beginSpray()`, `activeSprayCone`, and existing lifecycle methods.

- [ ] **Step 1: Add actual-spawn callback and nozzle state**

Add `onDidSpawn`, `nozzleEntity`, and retain the existing spray entity. Call `onDidSpawn?()` only after `install` has added the container, prepared audio, moved the session to `.available`, and notified state.

- [ ] **Step 2: Add twice-bounds interaction proxy**

After model centring, calculate the centred visual bounds and add a plain child entity with:

```swift
let interactionSize = centeredBounds.extents * 2
proxy.components.set(
    CollisionComponent(shapes: [ShapeResource.generateBox(size: interactionSize)])
)
proxy.components.set(InputTargetComponent())
proxy.components.set(HoverEffectComponent())
```

The proxy must remain a descendant of the extinguisher container and have no model/material.

- [ ] **Step 3: Add model-local hose nozzle anchor**

Place an `Entity` near the visible lower-left hose tip using centred normalized bounds:

```swift
let nozzle = Entity()
nozzle.name = "Fire extinguisher hose nozzle"
nozzle.position = SIMD3<Float>(
    centeredBounds.min.x + centeredBounds.extents.x * 0.18,
    centeredBounds.min.y + centeredBounds.extents.y * 0.10,
    centeredBounds.min.z - 0.01
)
container.addChild(nozzle)
nozzle.addChild(sprayEntity)
```

Keep the cone's local transform at identity.

- [ ] **Step 4: Derive the affected cone from the nozzle**

In `update`, continue positioning the held container from the stabilized head transform. Derive the apex and forward direction with RealityKit conversion:

```swift
let apex = nozzle.convert(position: .zero, to: nil)
let forwardPoint = nozzle.convert(position: SIMD3<Float>(0, 0, -1), to: nil)
let direction = forwardPoint - apex
```

Use those values for `currentSprayCone`. Do not separately apply a head-relative transform to `sprayEntity`.

- [ ] **Step 5: Make the cone brighter and double-sided**

Emit both `[0, next, current]` and `[0, current, next]` for every cone side. Replace the 0.24-opacity lit material with:

```swift
UnlitMaterial(color: UIColor.white.withAlphaComponent(0.45))
```

Keep cone length and angle unchanged.

- [ ] **Step 6: Clean nozzle/spray parenting on reset**

Disable and detach the spray entity in `clearAttempt`, clear `nozzleEntity`, then allow the next install to reparent the same retained spray entity.

- [ ] **Step 7: Run strict Debug simulator build and commit**

Use DerivedData `/tmp/respondR-extinguisher-reliability`, expect exit code 0, then:

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherController.swift'
git commit -m 'fix: improve extinguisher targeting and spray alignment'
```

---

### Task 3: Add floor-aware Gabe casualty lifecycle

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/MeshScanner.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/AppModel.swift`
- Create: `respondR/Resources/simulation (phase 2)/simulation/CasualtyController.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift`

**Interfaces:**

- Produces: `MeshScanner.randomFloorPosition(around:horizontalDistance:verticalOffset:) -> SIMD3<Float>?`.
- Produces: `CasualtyController.scheduleSpawn(deviceTransform:floorPosition:)`.
- Produces: `CasualtyController.contains(_:)`, `completeRescue()`, `update(deviceTransform:)`, `resetForAwaitingSpawn()`, and `cancel()`.
- Produces: `AppModel.maplessCasualtyID == "mapless-gabe"`.

- [ ] **Step 1: Add scanned-floor selection**

Iterate each anchor's indexed surface buckets with a per-anchor triangle-ID set so bucket duplication does not bias selection. Select triangle centres satisfying:

```swift
abs(triangle.normal.y) >= 0.75
horizontalDistance.contains(simd_length(SIMD2(delta.x, delta.z)))
verticalOffset.contains(delta.y)
```

Shuffle eligible centres and return one lifted by `SIMD3<Float>(0, 0.01, 0)`. The caller uses `6.5...7.5` metres and `-2.3 ... -0.5` metres.

- [ ] **Step 2: Register one casualty objective**

Add:

```swift
static let maplessCasualtyID = "mapless-gabe"
```

In Debug, begin the scenario with `[Self.maplessCasualtyID]` and update the status message to describe the mapless Gabe/fires while keeping Release Preparing behavior unchanged.

- [ ] **Step 3: Implement casualty preload and delayed spawn**

`CasualtyController` owns scene root, cached `gabe` template, preload task, spawn task, container, and phase (`waiting`, `available`, `carried`). `scheduleSpawn` clears the attempt, sleeps exactly five seconds, awaits preload, then polls valid tracked head and floor position every 250 milliseconds until cancelled.

- [ ] **Step 4: Install authored-size Gabe on scanned floor**

Clone the template, centre X/Z, place its minimum Y at container origin, generate recursive collision, enable input/hover recursively, apply random yaw, and install at the selected world floor position with uniform scale 1.

- [ ] **Step 5: Implement one-time carried state**

`completeRescue()` requires `.available`, moves to `.carried`, immediately disables the container, and removes collision/input/hover recursively. `update(deviceTransform:)` stores the latest tracked transform and, while carried, applies:

```swift
var transform = Transform(
    matrix: deviceTransform * translation(x: -0.32, y: -0.35, z: -0.65)
)
transform.scale = SIMD3<Float>(repeating: 0.2)
container.transform = transform
container.isEnabled = true
```

- [ ] **Step 6: Remove the obsolete Debug rescue shortcut**

Remove `AppModel.debugRescueNextCasualty()` and the `Rescue Next Casualty` control so mission state cannot say rescued while the spatial Gabe remains available. Update the Debug explanatory copy to say Gabe and fires use temporary mapless placement but the exit/map remain unavailable.

- [ ] **Step 7: Run strict Debug simulator build and commit**

Use DerivedData `/tmp/respondR-casualty-controller`, expect exit code 0, then:

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/MeshScanner.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/AppModel.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/CasualtyController.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift'
git commit -m 'feat: add delayed rescuable Gabe casualty'
```

---

### Task 4: Integrate casualty gestures, lifecycle, and blank-window removal

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift`
- Modify: `respondR/Models/AppSceneID.swift`
- Modify: `respondR/respondRApp.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift`

**Interfaces:**

- Consumes: extinguisher `onDidSpawn`, all `CasualtyController` methods, `AppSceneID.mainWindow`.
- Produces: complete reset/teardown and main-window reopen behavior.

- [ ] **Step 1: Create and preload the casualty controller**

Create it beside the extinguisher, bridge its errors to `appModel.errorMessage`, and preload Gabe. Wire `extinguisher.onDidSpawn` to:

```swift
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
```

- [ ] **Step 2: Update carried Gabe in the presentation loop**

Call `casualty.update(deviceTransform: stabilizedHead)` next to the extinguisher update. On missing tracking, pass `nil` so the carried entity retains its last valid pose.

- [ ] **Step 3: Route casualty pinch before extinguisher pinch**

For each active direct/indirect pinch, first test `casualty.contains(target)`. If true, call `appModel.recordCasualtyRescue(casualtyID: AppModel.maplessCasualtyID)`. On success call `casualty.completeRescue()` and set a concise rescue status. Return/continue before extinguisher routing. The spatial tap fire-start handler must also return early for casualty descendants.

- [ ] **Step 4: Reset and cancel casualty state everywhere**

Reset calls `resetForAwaitingSpawn()` without scheduling. Victory/defeat removes pending/world/carried state. Immersive disappearance calls `cancel()` and clears the controller reference.

- [ ] **Step 5: Give the existing main window a stable ID**

Replace the unused `phase2Controls` constant with `mainWindow = "MainWindow"` and declare:

```swift
WindowGroup(id: AppSceneID.mainWindow) {
    ContentView().environment(appModel)
}
```

Keep `.windowStyle(.volumetric)` and the existing default size.

- [ ] **Step 6: Dismiss main window only after immersion opens**

Add `@Environment(\.dismissWindow)` to `ControlWindowView`. In `.opened`, set app state, clear errors, then call:

```swift
dismissWindow(id: AppSceneID.mainWindow)
```

Do not dismiss on cancellation, error, or unsupported devices.

- [ ] **Step 7: Reopen main window and handle End Training inside immersion**

Add `openWindow` and `dismissImmersiveSpace` environments to `ImmersiveMeshView`. Observe `endTrainingTrigger` and dismiss the immersive space. In `onDisappear`, complete existing cleanup and call:

```swift
openWindow(id: AppSceneID.mainWindow)
```

The newly opened `ContentView` begins at phase selection.

- [ ] **Step 8: Run strict Debug simulator build and commit**

Use DerivedData `/tmp/respondR-casualty-integration`, expect exit code 0, then:

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift' \
  'respondR/Models/AppSceneID.swift' \
  'respondR/respondRApp.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift'
git commit -m 'feat: integrate casualty rescue and immersive window lifecycle'
```

---

### Task 5: Reconcile documentation and run final verification

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/scenario_plan.md`
- Review: all files modified in Tasks 1–4.

**Interfaces:** None.

- [ ] **Step 1: Update the scenario plan truthfully**

Record the single mapless Gabe lifecycle, actual-spawn-relative delay, 20%-scale lower-left carried state, twice-bounds extinguisher targeting, hose-nozzle cone, 1x-to-4x fire growth, and immersive main-window dismissal. Keep furniture anchors, mapped casualty placement, exit, alignment, and physical validation marked pending.

- [ ] **Step 2: Review the complete diff against the approved design**

Confirm every lifecycle entry and exit, no partial rescue, no Release fallback, no powder, no extinguished char, actual spawn timing, stable fire visual ordering, and exactly one WindowGroup.

- [ ] **Step 3: Run final strict builds**

Run Debug and Release for `generic/platform=visionOS Simulator` and Debug for `generic/platform=visionOS`, with separate DerivedData directories, `CODE_SIGNING_ALLOWED=NO`, and `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`.

- [ ] **Step 4: Run Xcode analysis**

Run Debug `analyze` for `generic/platform=visionOS Simulator` with a separate DerivedData directory and warnings as errors.

- [ ] **Step 5: Run repository and bundle checks**

```bash
plutil -lint respondR/Info.plist
git diff --check
rg -n 'mapless-gabe|6\.5\.\.\.7\.5|scale.*0\.2|extents \* 2|withAlphaComponent\(0\.45\)|1 \+ 3|AppSceneID\.mainWindow' respondR
git status --short
```

Confirm the Release app contains `gabe.usdz`, `Fire_Extinguisher.usdz`, and the updated `scenario_plan.md`, and confirm Release binary strings exclude Debug event-control labels.

- [ ] **Step 6: Commit documentation**

```bash
git add 'respondR/Resources/simulation (phase 2)/scenario_plan.md'
git commit -m 'docs: update casualty and fire scenario flow'
```

- [ ] **Step 7: Record physical-device gates without claiming them complete**

Report that gaze pickup, hose-tip alignment, seven-metre scanned-floor placement, perceived timing, lower-left carried comfort, 4x visual growth, and window dismissal/reopen still require a physical Apple Vision Pro run.
