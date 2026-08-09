# Phase 2 Fire Interaction and Peripheral HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start five random mapless fires from one deliberate scene pinch, spawn and reliably equip the extinguisher five seconds later, and move a smoothly stabilized HUD into peripheral vision.

**Architecture:** Keep random placement inside the pure fire grid/simulation boundary, expose only a one-shot fire-start state through `AppModel`, and route extinguisher gestures by entity and lifecycle phase. Split the 10 Hz simulation loop from an approximately 60 Hz presentation loop that stabilizes head-relative RealityKit attachments and the equipped extinguisher.

**Tech Stack:** Swift 6, SwiftUI, RealityKit, ARKit World Tracking, visionOS 27 SDK, Xcode 27 beta.

## Global Constraints

- Work on the existing `fire-simulator` branch.
- The first valid non-extinguisher scene pinch places exactly five fires once per attempt.
- Random candidates are 1.5–4.0 m away horizontally, 1.8–0.35 m below head height, and at least 0.8 m apart.
- Placement is atomic: fewer than five candidates means zero fires and no extinguisher countdown.
- The extinguisher is never installed before five seconds after successful placement.
- Pickup pinch equips but cannot spray until released; a later pinch-and-hold sprays.
- Mapless random placement is not a Release fallback for a missing or invalid anchor map.
- Keep the existing five-minute timer, rescue/exit victory rules, true-size extinguisher, cone, hiss, extinguish/no-char semantics, and natural-burn char behavior.
- No automated scenario tests. Use strict builds, analysis, source checks, and physical Vision Pro acceptance steps.

---

### Task 1: Add atomic five-fire selection and one-shot app state

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/FireGrid.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/AppModel.swift`

**Interfaces:**

- `FireGrid.occupiedCells(around:horizontalDistance:verticalOffset:) -> [SIMD3<Int32>]` returns occupied candidates only.
- `FireSimulation.igniteRandomFires(around:count:now:) -> [SIMD3<Float>]` atomically selects and ignites separated eligible cells.
- `AppModel.FireStartPhase` has `.awaitingFireStart` and `.started`.
- `AppModel.recordFireStarted() -> Bool` performs the single legal transition while the scenario is Active.

- [ ] **Step 1: Expose filtered occupied cells from `FireGrid`**

Add a method that computes horizontal X/Z distance and Y offset from the head position:

```swift
func occupiedCells(
    around origin: SIMD3<Float>,
    horizontalDistance: ClosedRange<Float>,
    verticalOffset: ClosedRange<Float>
) -> [SIMD3<Int32>] {
    occupied.filter { coordinate in
        let position = center(of: coordinate)
        let horizontal = simd_length(
            SIMD2<Float>(position.x - origin.x, position.z - origin.z)
        )
        return horizontalDistance.contains(horizontal)
            && verticalOffset.contains(position.y - origin.y)
    }
}
```

- [ ] **Step 2: Add atomic random ignition to `FireSimulation`**

Filter out runtime, burnt, and extinguished coordinates; shuffle candidates; greedily select positions at least 0.8 m apart; require `runtime.count + count <= maxActive`; and return `[]` without mutation unless exactly `count` cells were selected. Insert each chosen runtime using `igniteCell` and roll back only newly inserted cells if an unexpected insertion fails.

- [ ] **Step 3: Add the one-shot fire-start state to `AppModel`**

Reset `fireStartPhase` in `prepareScenario`, `beginScenario`, and `stopScenario`. Update mission guidance so Active plus `.awaitingFireStart` says `Pinch a scanned surface to start five fires.` Update extinguisher guidance so `.waitingToSpawn` after fire start says `Fire started. The extinguisher will arrive in five seconds.` and `.available` says `Look at the extinguisher and pinch to pick it up.`

- [ ] **Step 4: Run a strict Debug simulator build**

Run:

```bash
DEVELOPER_DIR=/Users/kc/Downloads/Xcode-beta.app/Contents/Developer xcodebuild -project respondR.xcodeproj -scheme respondR -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/respondR-fire-start-logic CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit the pure fire-start logic**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/FireGrid.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/FireSimulation.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/AppModel.swift'
git commit -m 'feat: add one-shot random fire start'
```

---

### Task 2: Decouple extinguisher loading from its delayed installation

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherController.swift`

**Interfaces:**

- `preloadAsset()` starts or reuses a cached template load without scene installation.
- `scheduleSpawn(deviceTransform:)` begins the five-second delay only after fire start and clones the cached template for installation.
- `resetForAwaitingFireStart()` removes equipment, spray, hiss, and delayed spawn while preserving a successful preload.
- `cancel()` additionally cancels and releases preload state on full immersive teardown.

- [ ] **Step 1: Add cached asset preloading**

Store `modelTemplate`, `preloadTask: Task<Void, Never>?`, and `preloadError`. Load `Entity(named: "Fire_Extinguisher", in: .main)` into the template once. Do not install it or change the session phase.

- [ ] **Step 2: Make spawn delay fire-event-driven**

In `scheduleSpawn`, reset the attempt while preserving preload state, ensure preload exists, sleep for exactly five seconds, await the pending preload if necessary, clone the template recursively, obtain a valid tracked device pose, and call the existing `install`. Never call this method from immersive entry or reset.

- [ ] **Step 3: Separate attempt reset from full cancellation**

`resetForAwaitingFireStart()` cancels `spawnTask`, stops audio, hides the cone, removes the installed extinguisher, and resets `FireExtinguisherSession`, but keeps the template/preload. `cancel()` performs the same cleanup and also cancels/releases preload state.

- [ ] **Step 4: Run a strict Debug simulator build**

Use the Task 1 build command with DerivedData `/tmp/respondR-extinguisher-preload`.

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit the controller lifecycle**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/FireExtinguisherController.swift'
git commit -m 'fix: start extinguisher delay after fire ignition'
```

---

### Task 3: Route gestures by state and add smooth peripheral presentation

**Files:**

- Create: `respondR/Resources/simulation (phase 2)/simulation/HeadFollowSmoother.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/HUDView.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift`

**Interfaces:**

- `HeadFollowSmoother.update(target:deltaTime:) -> simd_float4x4` returns an exponentially stabilized head pose using translation mixing and quaternion slerp.
- `HeadFollowSmoother.reset()` clears retained pose.
- `HUDStatusView` renders health, challenges, mission guidance, and extinguisher guidance without a full-screen canvas.
- `HUDTimerView` renders only the countdown.

- [ ] **Step 1: Implement frame-rate-independent transform stabilization**

Use a response rate derived from the approved approximately 120 ms window:

```swift
let alpha = Float(1 - exp(-deltaTime / 0.12))
translation = simd_mix(current.translation, target.translation, SIMD3(repeating: alpha))
rotation = simd_slerp(current.rotation, target.rotation, alpha)
```

Return the first target immediately and clamp negative delta time to zero.

- [ ] **Step 2: Split the HUD into status and timer attachments**

Refactor the current panel code into `HUDStatusView` and `HUDTimerView`. The status view stacks health, scenario progress, and optional extinguisher guidance. Both retain `.glassBackgroundEffect()`, semantic colours, Dynamic Type styles, Reduce Motion handling, and accessibility values.

- [ ] **Step 3: Split simulation and presentation tasks in `ImmersiveMeshView`**

Keep fire tick, spread, char, damage, and scenario countdown at 100 ms. Add `presentationTask` at approximately 16 ms that queries the head pose, updates the equipped extinguisher, advances `HeadFollowSmoother`, and positions:

```swift
status: x = -0.45, y = 0.25, z = -1.15
timer:  x =  0.45, y = 0.25, z = -1.15
result: x =  0.00, y = 0.00, z = -0.95
```

Toggle status/timer off and result on when `scenarioOutcome` becomes non-nil.

- [ ] **Step 4: Start five fires once and only then schedule the extinguisher**

Remove initial and reset-time `scheduleSpawn` calls. In the non-extinguisher `SpatialTapGesture.onEnded` path, require Active plus `.awaitingFireStart`, require a valid head pose, call `igniteRandomFires(around:count:now:)`, require five returned positions, call `recordFireStarted`, and schedule the controller. On failure, show `Look around to scan more surfaces, then pinch again.`

- [ ] **Step 5: Equip on active pinch and latch pickup until release**

Track `pickupPinchInProgress`. When a direct or indirect active pinch targets the extinguisher:

- `.available`: call `pickUp()` immediately and set the latch.
- `.equipped` with no latch: call `beginSpray()`.
- `.waitingToSpawn`: do nothing.

On ended or cancelled events, call `endSpray()` and clear the latch. The scene tap handler must always return early when its target belongs to the extinguisher hierarchy.

- [ ] **Step 6: Reset and teardown every task and interaction latch**

Reset clears fire/char, app fire-start state, pickup latch, smoother, and controller attempt state without scheduling a spawn. Disappearance cancels both tasks and fully cancels the controller.

- [ ] **Step 7: Update control-window guidance**

Replace `Tap a surface to ignite.` with `Pinch a scanned surface once to start five fires.` in Debug-only guidance.

- [ ] **Step 8: Run a strict Debug simulator build**

Use the Task 1 build command with DerivedData `/tmp/respondR-peripheral-hud`.

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit the integrated interaction and presentation flow**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/HeadFollowSmoother.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/HUDView.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift'
git commit -m 'feat: improve extinguisher gestures and peripheral hud'
```

---

### Task 4: Add Digital Crown guidance and update scenario documentation

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/ScenarioResultView.swift`
- Modify: `respondR/Resources/simulation (phase 2)/scenario_plan.md`

**Interfaces:**

- Victory and defeat both render the exact secondary copy `Press the Digital Crown to exit.`

- [ ] **Step 1: Add result-screen guidance**

Place the exact copy below the result actions using `.callout.weight(.semibold)`, `.foregroundStyle(.secondary)`, centred text, and an explicit accessibility label.

- [ ] **Step 2: Reconcile `scenario_plan.md` with implemented mapless behavior**

Record the one-shot five-fire placement, post-fire extinguisher delay, pickup latch, peripheral HUD, smooth presentation loop, and Digital Crown copy. Replace stale claims that Debug has no fire positions or that reset immediately schedules the extinguisher. Keep furniture anchoring, casualty/exit transforms, alignment, and physical validation clearly blocked.

- [ ] **Step 3: Commit result copy and documentation**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/ScenarioResultView.swift' \
  'respondR/Resources/simulation (phase 2)/scenario_plan.md'
git commit -m 'docs: update phase 2 result and mapless flow'
```

---

### Task 5: Final review and verification

**Files:**

- Review all files modified by Tasks 1–4.

**Interfaces:** None.

- [ ] **Step 1: Review the complete diff against the approved design**

Confirm: five atomic fires; one-shot scene start; countdown starts after success; pickup pinch cannot spray; later hold sprays; reset returns to awaiting start; status left, timer right; centre clear; result copy exact; Release has no random fallback.

- [ ] **Step 2: Run final strict builds in isolated DerivedData directories**

Run Debug and Release for `generic/platform=visionOS Simulator` and Debug for `generic/platform=visionOS`, all with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and `CODE_SIGNING_ALLOWED=NO`.

- [ ] **Step 3: Run Xcode analysis**

Run Debug `analyze` for `generic/platform=visionOS Simulator` with DerivedData `/tmp/respondR-fire-final-analyze`.

- [ ] **Step 4: Run static repository checks**

```bash
plutil -lint respondR/Info.plist
git diff --check
rg -n 'Press the Digital Crown to exit\.' 'respondR/Resources/simulation (phase 2)/simulation/ScenarioResultView.swift'
git status --short
```

- [ ] **Step 5: Record physical-device gates without claiming them complete**

Report that gaze targeting, five-second perceived timing, live random placement, head-follow comfort, and Crown behavior still require a physical Apple Vision Pro run.
