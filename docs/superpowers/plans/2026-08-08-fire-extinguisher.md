# Phase 2 Fire Extinguisher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a true-size pickup extinguisher to Phase 2 whose held pinch shows a white cone, plays a hiss, and removes fire without creating char.

**Architecture:** Keep cone containment, scale calculation, and extinguisher state transitions in platform-independent Swift values exercised by a standalone core check. Extend `FireSimulation` with an explicit manual-extinguish path, then keep RealityKit asset/audio/entity lifecycle inside one main-actor controller wired into the existing immersive tick and HUD.

**Tech Stack:** Swift 5 mode, SwiftUI, RealityKit, ARKit device anchors, AVFAudio real-time render blocks, visionOS 27, USDZ.

## Global Constraints

- Use `respondR/Resources/Fire_Extinguisher.usdz`; do not substitute procedural extinguisher geometry.
- Normalize the loaded model to exactly 0.55 metres tall.
- Spawn after five seconds only in Phase 2 fire mode; reset starts a fresh five-second cycle.
- Pickup permanently equips for the current immersive session; there is no inventory UI.
- The spray cone is translucent white, two metres long, and has a 17.5-degree half-angle.
- The cone and hiss exist only while a pinch remains active; otherwise both are absent.
- Manual extinguishing removes damage and spread immediately and never queues char.
- Natural burnout retains the existing black-char lifecycle.
- Preserve the user's unrelated untracked USDZ files.
- Simulator/build evidence does not replace physical Apple Vision Pro interaction and audio acceptance.

---

## File structure

- Create `respondR/Resources/simulation (phase 2)/simulation/SprayCone.swift`: pure cone containment and direction normalization.
- Create `respondR/Resources/simulation (phase 2)/simulation/ExtinguisherSizing.swift`: pure bounds-to-target uniform scale calculation.
- Create `respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherSession.swift`: pure waiting/available/equipped/spraying state transitions.
- Create `respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherController.swift`: RealityKit asset, entity, cone, audio, delayed-spawn, pose, and cleanup lifecycle.
- Create `Tests/FireExtinguisherCoreCheck.swift`: executable behavior checks compiled with the pure production sources.
- Modify `respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift`: remove active cells inside a `SprayCone` without entering `pendingBurnt`.
- Modify `respondR/Resources/simulation (phase 2)/simulation/AppModel.swift`: expose extinguisher phase and concise guidance to the HUD.
- Modify `respondR/Resources/simulation (phase 2)/simulation/HUDView.swift`: show only the current one- or two-line instruction.
- Modify `respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift`: create/controller lifecycle, pickup and held-pinch input, tick extinguishing, pose updates, reset, and exit cleanup.
- Track `respondR/Resources/Fire_Extinguisher.usdz`: bundle the user-supplied required asset; leave the other new USDZ files untracked.

---

### Task 1: Pure spray geometry and scale normalization

**Files:**
- Create: `Tests/FireExtinguisherCoreCheck.swift`
- Create: `respondR/Resources/simulation (phase 2)/simulation/SprayCone.swift`
- Create: `respondR/Resources/simulation (phase 2)/simulation/ExtinguisherSizing.swift`

**Interfaces:**
- Produces: `SprayCone.init(apex:direction:maxDistance:halfAngleRadians:)`, `SprayCone.contains(_:padding:)`, and `ExtinguisherSizing.uniformScale(currentHeight:targetHeight:)`.
- Consumes: `SIMD3<Float>` and `simd` only.

- [ ] **Step 1: Write the failing core checks**

Create `Tests/FireExtinguisherCoreCheck.swift` with an `@main` executable, literal expected values, and checks that would fail if direction normalization, behind/beyond rejection, radial-angle comparison, zero-height validation, or scale division is wrong:

```swift
import Foundation
import simd

@main
enum FireExtinguisherCoreCheck {
    static func main() {
        let cone = SprayCone(
            apex: .zero,
            direction: SIMD3<Float>(0, 0, -4),
            maxDistance: 2,
            halfAngleRadians: 17.5 * .pi / 180
        )

        require(cone.contains(SIMD3<Float>(0, 0, -1)), "axis point must be inside")
        require(cone.contains(SIMD3<Float>(0.25, 0, -1)), "near-edge point must be inside")
        require(!cone.contains(SIMD3<Float>(0.5, 0, -1)), "wide point must be outside")
        require(!cone.contains(SIMD3<Float>(0, 0, 0.1)), "point behind apex must be outside")
        require(!cone.contains(SIMD3<Float>(0, 0, -2.1)), "point beyond reach must be outside")
        require(cone.contains(SIMD3<Float>(0.38, 0, -1), padding: 0.1), "cell padding must expand coverage")

        require(
            ExtinguisherSizing.uniformScale(currentHeight: 2, targetHeight: 0.55) == 0.275,
            "two-metre asset must scale to 0.55 metres"
        )
        require(
            ExtinguisherSizing.uniformScale(currentHeight: 0, targetHeight: 0.55) == nil,
            "zero-height bounds must be rejected"
        )

        runSimulationChecks()
        runSessionChecks()
        print("Fire extinguisher core checks passed")
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func runSimulationChecks() {}
    static func runSessionChecks() {}
}
```

- [ ] **Step 2: Run the core-check compile and verify RED**

Run:

```bash
DEVELOPER_DIR=/Users/kc/Downloads/Xcode-beta.app/Contents/Developer xcrun swiftc \
  'respondR/Resources/simulation (phase 2)/simulation/FireGrid.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift' \
  Tests/FireExtinguisherCoreCheck.swift \
  -o /tmp/respondr-fire-extinguisher-core-check
```

Expected: compilation fails because `SprayCone` and `ExtinguisherSizing` do not exist.

- [ ] **Step 3: Implement the minimal pure values**

Implement `SprayCone` with a normalized direction, axial projection in `(0...maxDistance)`, and radial allowance `projection * tan(halfAngleRadians) + padding`. Implement `ExtinguisherSizing.uniformScale` to return `nil` unless both heights are finite and positive, otherwise return `targetHeight / currentHeight`.

```swift
import Foundation
import simd

struct SprayCone {
    let apex: SIMD3<Float>
    let direction: SIMD3<Float>
    let maxDistance: Float
    let halfAngleRadians: Float

    init(apex: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float, halfAngleRadians: Float) {
        self.apex = apex
        self.direction = simd_length_squared(direction) > 0 ? simd_normalize(direction) : SIMD3(0, 0, -1)
        self.maxDistance = max(0, maxDistance)
        self.halfAngleRadians = max(0, halfAngleRadians)
    }

    func contains(_ point: SIMD3<Float>, padding: Float = 0) -> Bool {
        let offset = point - apex
        let projection = simd_dot(offset, direction)
        guard projection >= 0, projection <= maxDistance else { return false }
        let radial = simd_length(offset - direction * projection)
        return radial <= projection * tan(halfAngleRadians) + max(0, padding)
    }
}
```

- [ ] **Step 4: Compile and run the checks to verify GREEN**

Add both new production files to the command from Step 2, run the binary, and expect `Fire extinguisher core checks passed` with exit status 0.

- [ ] **Step 5: Commit the pure geometry slice**

```bash
git add Tests/FireExtinguisherCoreCheck.swift \
  'respondR/Resources/simulation (phase 2)/simulation/SprayCone.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ExtinguisherSizing.swift'
git commit -m 'test: define extinguisher spray geometry'
```

---

### Task 2: Manual extinguishing without char

**Files:**
- Modify: `Tests/FireExtinguisherCoreCheck.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift:51-133`

**Interfaces:**
- Consumes: `SprayCone.contains(_:padding:)` from Task 1.
- Produces: `@discardableResult func extinguish(in cone: SprayCone) -> [SIMD3<Float>]`.

- [ ] **Step 1: Replace `runSimulationChecks()` with failing behavior checks**

Use a 0.30-metre grid, insert literal cell centres, ignite the two forward cells, extinguish with a narrow two-metre cone, and assert that only the on-axis fire disappears, cannot re-ignite, and leaves `drainNewlyBurnt()` empty. In a second simulation with a 0.1-second burn duration, advance ignition and burn ticks and assert natural burnout still queues one char position.

```swift
static func runSimulationChecks() {
    let onAxis = SIMD3<Float>(0.15, 0.15, -0.45)
    let outside = SIMD3<Float>(0.75, 0.15, -0.45)
    let cone = SprayCone(apex: .zero, direction: SIMD3(0, 0, -1), maxDistance: 2, halfAngleRadians: 17.5 * .pi / 180)

    let manual = FireSimulation(cellSize: 0.30, spreadInterval: 100)
    manual.insertGeometry([onAxis, outside])
    require(manual.ignite(at: onAxis, now: 0), "first fire must ignite")
    require(manual.ignite(at: outside, now: 0), "second fire must ignite")
    require(manual.extinguish(in: cone).count == 1, "cone must remove only the covered fire")
    require(manual.activeCount == 1, "uncovered fire must remain active")
    require(manual.drainNewlyBurnt().isEmpty, "manual removal must not queue char")
    require(!manual.ignite(at: onAxis, now: 1), "extinguished fire must not re-ignite")

    let natural = FireSimulation(cellSize: 0.30, ignitionDuration: 0.1, burnDuration: 0.1, spreadInterval: 100)
    natural.insertGeometry([onAxis])
    require(natural.ignite(at: onAxis, now: 0), "natural fire must ignite")
    natural.tick(now: 0.11)
    natural.tick(now: 0.22)
    require(natural.activeCount == 0, "expired fire must leave the active set")
    require(natural.drainNewlyBurnt().count == 1, "natural burnout must queue char")
}
```

- [ ] **Step 2: Compile and verify RED**

Run the Task 1 command with all pure sources. Expected: compilation fails because `FireSimulation.extinguish(in:)` is missing.

- [ ] **Step 3: Implement the manual removal path**

Iterate over a snapshot of `runtime.keys`; when the cell centre is inside the cone using `grid.cellSize * 0.5` as padding, remove it from `runtime`, add it to a separate terminal `extinguished` set, and append its centre to the return value. The ignition guard rejects both burnt and extinguished cells. Do not mutate `burnt` or `pendingBurnt`, and clear `extinguished` on reset.

```swift
@discardableResult
func extinguish(in cone: SprayCone) -> [SIMD3<Float>] {
    var removed: [SIMD3<Float>] = []
    for coord in Array(runtime.keys) {
        let position = grid.center(of: coord)
        if cone.contains(position, padding: grid.cellSize * 0.5) {
            runtime[coord] = nil
            extinguished.insert(coord)
            removed.append(position)
        }
    }
    return removed
}
```

- [ ] **Step 4: Run the core checks to verify GREEN**

Expected: both selective-extinguishing and natural-burnout checks pass, with an empty char queue for manual removal and one queued position for natural burnout.

- [ ] **Step 5: Commit the simulation slice**

```bash
git add Tests/FireExtinguisherCoreCheck.swift \
  'respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift'
git commit -m 'feat: extinguish active fire without char'
```

---

### Task 3: Deterministic equipment and spray state

**Files:**
- Create: `respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherSession.swift`
- Modify: `Tests/FireExtinguisherCoreCheck.swift`

**Interfaces:**
- Produces: `FireExtinguisherSession.Phase` (`waitingToSpawn`, `available`, `equipped`), `phase`, `isSpraying`, `didSpawn()`, `pickUp()`, `beginSpray()`, `endSpray()`, and `reset()`.
- Consumes: no platform frameworks.

- [ ] **Step 1: Replace `runSessionChecks()` with failing transition checks**

Assert that spray cannot start while waiting or available, `didSpawn()` makes pickup possible, pickup permanently enters equipped state, held spray toggles only `isSpraying`, end spray preserves equipment, and reset returns to waiting with spray false.

```swift
static func runSessionChecks() {
    var session = FireExtinguisherSession()
    require(session.phase == .waitingToSpawn, "session must start waiting")
    require(!session.beginSpray(), "spray before pickup must be rejected")
    session.didSpawn()
    require(session.phase == .available, "spawn must make extinguisher available")
    require(!session.beginSpray(), "available extinguisher must not spray before pickup")
    require(session.pickUp(), "available extinguisher must be pickable")
    require(session.phase == .equipped, "pickup must permanently equip")
    require(session.beginSpray() && session.isSpraying, "held pinch must start spray")
    session.endSpray()
    require(session.phase == .equipped && !session.isSpraying, "release must stop spray but keep equipment")
    session.reset()
    require(session.phase == .waitingToSpawn && !session.isSpraying, "reset must clear equipment and spray")
}
```

- [ ] **Step 2: Compile and verify RED**

Expected: compilation fails because `FireExtinguisherSession` is missing.

- [ ] **Step 3: Implement the minimal state machine**

Use a value type with guarded mutating transitions. `beginSpray()` and `pickUp()` return `Bool` so adapters can ignore invalid input without side effects.

```swift
struct FireExtinguisherSession {
    enum Phase: Equatable {
        case waitingToSpawn
        case available
        case equipped
    }

    private(set) var phase: Phase = .waitingToSpawn
    private(set) var isSpraying = false

    mutating func didSpawn() { if phase == .waitingToSpawn { phase = .available } }

    @discardableResult
    mutating func pickUp() -> Bool {
        guard phase == .available else { return false }
        phase = .equipped
        return true
    }

    @discardableResult
    mutating func beginSpray() -> Bool {
        guard phase == .equipped else { return false }
        isSpraying = true
        return true
    }

    mutating func endSpray() { isSpraying = false }

    mutating func reset() {
        phase = .waitingToSpawn
        isSpraying = false
    }
}
```

- [ ] **Step 4: Run all core checks to verify GREEN**

Expected: geometry, scale, extinguishing, char, and session checks all pass.

- [ ] **Step 5: Commit the session slice**

```bash
git add Tests/FireExtinguisherCoreCheck.swift \
  'respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherSession.swift'
git commit -m 'feat: model extinguisher session state'
```

---

### Task 4: RealityKit extinguisher controller and bundled asset

**Files:**
- Create: `respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherController.swift`
- Track: `respondR/Resources/Fire_Extinguisher.usdz`

**Interfaces:**
- Consumes: `FireExtinguisherSession`, `ExtinguisherSizing`, `SprayCone`, an entity root, and a device-transform provider.
- Produces: `scheduleSpawn(deviceTransform: @escaping @MainActor () -> simd_float4x4?)`, `contains(_:)`, `pickUp()`, `beginSpray()`, `endSpray()`, `update(deviceTransform:)`, `activeSprayCone`, `resetAndSchedule(deviceTransform:)`, `cancel()`, `onStateChange: ((FireExtinguisherSession.Phase, Bool) -> Void)?`, and `onError: ((String) -> Void)?`.

- [ ] **Step 1: Implement delayed load and spawn with explicit cleanup**

Preload `Fire_Extinguisher.usdz` during a cancellable five-second task, normalize its visual bounds to 0.55 metres, generate recursive collision/input/hover targeting, and apply the approved device-relative world transform only after the delay. Keep the spawned entity world-fixed until pickup.

- [ ] **Step 2: Implement equipped placement and matching cone geometry**

Reposition the same model each tick using the current device transform and lower-right held offset. Build a low-segment `MeshDescriptor` cone extending from local origin down local negative Z, use translucent white `SimpleMaterial`, disable it initially, and update its world transform from the same device pose. `activeSprayCone` must be `nil` unless the session is actively spraying.

- [ ] **Step 3: Implement procedural spatial hiss**

Prepare an `AudioGeneratorController` on the extinguisher with mono `AudioGeneratorConfiguration` and an `AVAudioSourceNodeRenderBlock` that fills every output buffer with low-gain filtered pseudo-random noise. Start on `beginSpray()`, stop on `endSpray()`, and catch audio preparation failure without disabling visual spray or extinguishing.

- [ ] **Step 4: Build the simulator target as the adapter integration check**

Run the baseline simulator build command. Resolve only controller/API compilation errors; expect `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit controller and required asset only**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherController.swift' \
  respondR/Resources/Fire_Extinguisher.usdz
git commit -m 'feat: add spatial fire extinguisher controller'
```

---

### Task 5: Immersive input, fire tick, cleanup, and concise HUD guidance

**Files:**
- Modify: `respondR/Resources/simulation (phase 2)/simulation/AppModel.swift:14-43`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/HUDView.swift:7-23`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift:6-155`

**Interfaces:**
- Consumes: all Task 1-4 controller and simulation interfaces.
- Produces: the approved end-to-end Phase 2 interaction.

- [ ] **Step 1: Add observable HUD state and exact guidance copy**

Add `extinguisherPhase` to `AppModel`, plus a computed optional string that is `nil` while waiting, `"Tap the extinguisher to pick it up."` when available, and `"Pinch and hold the extinguisher to spray. Aim the white cone at the fire."` when equipped. Add one compact, accessible material-backed instruction surface to the head-following HUD only when the string is non-nil.

- [ ] **Step 2: Create and schedule the controller in fire mode**

Construct it beside `FireSimulation`, route its state callback into `appModel.extinguisherPhase`, route errors into `appModel.errorMessage`, and schedule the five-second spawn with `scanner.queryHeadTransform()`.

- [ ] **Step 3: Intercept pickup before tap-to-ignite**

In the existing `SpatialTapGesture`, first ask whether the tapped entity belongs to the extinguisher. If so, call `pickUp()` and return; otherwise retain the existing surface ignition behavior exactly.

- [ ] **Step 4: Add held-pinch start/end input**

Add a simultaneous `SpatialEventGesture`. For `.active` direct or indirect pinch events targeting the extinguisher, call `beginSpray()`. For `.ended` or `.cancelled` events while spraying, call `endSpray()`. This gesture is the only path that changes cone and hiss playback.

- [ ] **Step 5: Extinguish before rendering and damage calculation**

On every 100-millisecond tick, query the device transform once, update the held entity/cone pose, call `sim.extinguish(in:)` only when `activeSprayCone` is non-nil, then obtain active positions, sync fire rendering, drain natural burns, and calculate proximity damage. Passing post-extinguish active positions guarantees removed fire stops damage during the same update.

- [ ] **Step 6: Reset and exit without lingering state**

On reset, clear the simulation/renderers/HUD and call `resetAndSchedule`. On disappearance, cancel the controller before clearing the remaining view state. Verify the controller always hides the cone and stops audio before entity removal.

- [ ] **Step 7: Run core checks and simulator build**

Expected: standalone checks print `Fire extinguisher core checks passed`; simulator build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit the end-to-end integration**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/AppModel.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/HUDView.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift'
git commit -m 'feat: wire phase 2 extinguisher interaction'
```

---

### Task 6: Full verification and review

**Files:**
- Review all files changed by Tasks 1-5.

**Interfaces:**
- Consumes: the complete feature.
- Produces: fresh local evidence and an explicit physical-hardware gate.

- [ ] **Step 1: Run the complete standalone core check**

Compile all pure sources and expect the success message and exit status 0.

- [ ] **Step 2: Run simulator and generic-device builds**

Use separate derived-data paths with `CODE_SIGNING_ALLOWED=NO`; expect `** BUILD SUCCEEDED **` for both `generic/platform=visionOS Simulator` and `generic/platform=visionOS`.

- [ ] **Step 3: Run Xcode analysis and repository checks**

Run `xcodebuild ... analyze`, `plutil -lint respondR/Info.plist`, `git diff --check`, and inspect `git status --short`. Confirm only the extinguisher asset among the user's five new USDZ files was added.

- [ ] **Step 4: Review requirement-by-requirement**

Confirm: delayed spawn; true size; permanent session pickup; no inventory; cone/hiss only while held; cone matches math; extinguished fire disappears, cannot spread or damage, and queues no char; natural burnout still chars; reset/exit cleanup; concise guidance.

- [ ] **Step 5: Record the hardware acceptance boundary**

Report that live spawn comfort, gaze aiming, held-pinch cancellation, spatial hiss quality, and real-room fire targeting still require a signed physical Apple Vision Pro run.
