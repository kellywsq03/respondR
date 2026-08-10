# Phase 2 Fire Training Scenario Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement every anchor-independent part of the fixed five-minute Phase 2 rescue scenario while leaving real fire, casualty, exit, and alignment integration explicitly blocked until the anchor map arrives.

**Architecture:** A focused `ScenarioSession` value owns mission phase, the fixed timer, casualty IDs, idempotent rescue progress, and deterministic victory/defeat evaluation. `AppModel` bridges that state into the existing SwiftUI control window and RealityKit immersive loop; the real anchor adapter will later emit the same rescue and exit events without changing outcome logic.

**Tech Stack:** Swift 5, SwiftUI, Observation, RealityKit, ARKit, visionOS 27, Xcode 27 beta.

## Global Constraints

- Use the existing branded native SwiftUI/RealityKit track and `.glassBackgroundEffect()` spatial surfaces.
- The timer is always exactly 300 seconds; do not add settings or configuration UI.
- Fires are hazards, never a completion objective.
- Do not create temporary RealityKit casualty entities, exit entities, transforms, or head-relative fallbacks.
- Debug controls may emit production mission events but must be inside `#if DEBUG`.
- The user explicitly declined automated scenario tests. Do not add a test suite; use strict builds, Xcode analysis, debug-flow inspection, and the documented physical-device gate.
- Keep the moved plan at `respondR/Resources/simulation (phase 2)/scenario_plan.md` and mark implemented versus anchor-blocked scope in it.
- Do not implement or claim live anchor-map behavior without the map.

## UI decision brief

- Surface type: Native spatial task flow with a live HUD and modal debrief attachment.
- Platform idiom: Branded native Apple visionOS using SwiftUI attachments and RealityKit placement.
- Product thesis: Keep the learner oriented around health, casualties, time, and the next safe action.
- Visual direction: Existing emergency-response identity with restrained semantic red, green, orange, and native materials.
- Density: Balanced; health and casualty progress lead, timer remains bottom-right, extinguisher guidance remains bottom-left.
- Hierarchy: Live mission status first; debrief title and Try Again action dominate only after an outcome.
- Component grammar: Glass-backed HUD panels, a centered result surface, native `Button`, SF Symbols, semantic colors, and Dynamic Type styles.
- Motion budget: Subtle spring transitions only, with nonessential transitions removed under Reduce Motion.
- Accessibility: Combined labels for health, progress, timer, outcome, and buttons; update traits for changing values.
- Rejected: Temporary spatial content, custom icon libraries, decorative particle celebrations, and dense score dashboards.

---

### Task 1: Preserve the moved scenario specification and implementation plan

**Files:**
- Move already performed by user: `scenario_plan.md` → `respondR/Resources/simulation (phase 2)/scenario_plan.md`
- Create: `docs/superpowers/plans/2026-08-08-fire-training-scenario.md`

**Interfaces:**
- Consumes: the approved scenario contract.
- Produces: the source-of-truth product plan and this executable engineering plan.

- [ ] **Step 1: Confirm only the intended rename and implementation plan are pending**

Run:

```bash
git status --short
git diff --check
```

- [ ] **Step 2: Commit the planning slice**

```bash
git add scenario_plan.md \
  'respondR/Resources/simulation (phase 2)/scenario_plan.md' \
  docs/superpowers/plans/2026-08-08-fire-training-scenario.md
git commit -m 'docs: plan phase 2 rescue scenario'
```

---

### Task 2: Add deterministic scenario state and AppModel integration

**Files:**
- Create: `respondR/Resources/simulation (phase 2)/simulation/ScenarioSession.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/AppModel.swift`

**Interfaces:**
- Produces: `ScenarioSession.Phase`, `DefeatReason`, `Outcome`, fixed `duration`, `start(requiredCasualtyIDs:)`, `advance(by:)`, `rescue(casualtyID:)`, `reachExit()`, `depleteHealth()`, `prepare()`, and `stop()`.
- Produces AppModel bridges: `scenarioPhase`, `scenarioOutcome`, casualty counts, mission guidance, `beginScenario`, debug preview start, event methods, and reset/end triggers.

- [ ] **Step 1: Implement `ScenarioSession` as a focused value type**

Use these state contracts:

```swift
struct ScenarioSession {
    static let duration: TimeInterval = 5 * 60

    enum Phase: Equatable { case preparing, active, victory, defeat }
    enum DefeatReason: Equatable { case timeExpired, healthDepleted, casualtiesLeftBehind }

    struct Outcome: Equatable {
        let isVictory: Bool
        let defeatReason: DefeatReason?
        let timeUsed: TimeInterval
        let rescuedCount: Int
        let totalCasualties: Int
    }
}
```

`start` rejects an empty list and duplicate IDs. `rescue` is idempotent. `reachExit` resolves victory only when all registered casualties are rescued and time remains. Outcome methods do nothing outside Active so a result is emitted once.

- [ ] **Step 2: Replace the 30-minute HUD timer with the session's fixed timer**

Expose `timeRemaining`, `formattedTimeRemaining`, and `isScenarioActive` as AppModel computed properties. Keep health and proximity exposure in AppModel, but only advance them while the scenario is Active.

- [ ] **Step 3: Connect timer expiry and zero health to defeat**

`updateScenario(deltaTime:isNearActiveFire:)` advances timer and health from real elapsed time. Once health reaches zero, call the session's health defeat event. Do not drain health or time outside Active.

- [ ] **Step 4: Add Debug-only event validation**

In Debug builds, start an event-only preview with two stable casualty identifiers. Expose methods to rescue the next casualty, reach the exit, expire the timer, and deplete health. Release builds remain Preparing until the anchor adapter calls `beginScenario` with real IDs.

- [ ] **Step 5: Strict-compile the state slice**

Run the generic simulator build with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` before committing.

- [ ] **Step 6: Commit**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/ScenarioSession.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/AppModel.swift'
git commit -m 'feat: add phase 2 scenario state'
```

---

### Task 3: Add mission HUD and spatial debrief

**Files:**
- Modify: `respondR/Resources/simulation (phase 2)/simulation/HUDView.swift`
- Create: `respondR/Resources/simulation (phase 2)/simulation/ScenarioResultView.swift`

**Interfaces:**
- Consumes: AppModel casualty progress, guidance, scenario phase, outcome, reset trigger, and end-training trigger.
- Produces: an accessible casualty objective panel and interactive victory/defeat result surface.

- [ ] **Step 1: Add casualty progress below health**

Show `CASUALTIES X/N` and mission guidance. Preparing displays the anchor-map-required message; Active displays remaining count or `All casualties rescued. Find the exit.` Do not add fire progress.

- [ ] **Step 2: Implement the debrief surface**

Create a centered branded-native material surface with exact approved victory/defeat copy, the appropriate defeat reason, time used, `X/N` casualty result, a primary `Try Again` button, and a secondary `End Training` button.

- [ ] **Step 3: Preserve accessibility and motion constraints**

Use semantic text styles, SF Symbols, native buttons, combined accessibility labels, and spring-only state transitions guarded by Reduce Motion.

- [ ] **Step 4: Strict-compile and commit**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/HUDView.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ScenarioResultView.swift'
git commit -m 'feat: add scenario objectives and debrief'
```

---

### Task 4: Integrate scenario lifecycle, debug controls, and cleanup

**Files:**
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift`
- Modify: `respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift`

**Interfaces:**
- Consumes: ScenarioSession/AppModel events and existing extinguisher/fire systems.
- Produces: paused-on-outcome simulation, complete reset, centered result attachment, and Debug-only event controls.

- [ ] **Step 1: Start the correct scenario path**

On entering fire mode, call AppModel preparation. Debug builds start the event-only preview; Release builds remain Preparing with a clear map-unavailable message. Do not fabricate map content.

- [ ] **Step 2: Pause simulation and input after an outcome**

Continue positioning the HUD and result attachments from the head pose, but only tick fire spread, extinguishing, damage, casualty input, exit input, and free-form fire ignition while Active. Stop the spray cone and hiss as soon as Active ends.

- [ ] **Step 3: Add and position the result attachment**

Add `ScenarioResultView` as a RealityView attachment and place it 0.85 metres ahead of the current head pose. The existing HUD remains noninteractive; the result attachment retains button hit testing.

- [ ] **Step 4: Make reset complete**

Try Again and the control-window reset use one request path that clears fire, char, health exposure, timer, objectives, outcome, extinguisher state, cone, and hiss, then restarts the Debug preview or awaits real map content in Release.

- [ ] **Step 5: Make End Training complete**

The result button raises an AppModel end-training trigger. `ControlWindowView` dismisses the immersive space and returns to Phase Selection through its existing async lifecycle.

- [ ] **Step 6: Add Debug-only controls**

Under `#if DEBUG`, add native buttons for Rescue Next Casualty, Reach Exit, Expire Timer, Deplete Health, and Reset Scenario. Label the group as event-only and state that no anchor map or spatial entities are present.

- [ ] **Step 7: Strict-compile and commit**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift' \
  'respondR/Resources/simulation (phase 2)/simulation/ControlWindowView.swift'
git commit -m 'feat: integrate phase 2 scenario flow'
```

---

### Task 5: Record implementation status and verify the deliverable

**Files:**
- Modify: `respondR/Resources/simulation (phase 2)/scenario_plan.md`

**Interfaces:**
- Consumes: final code and verification evidence.
- Produces: explicit Implemented, Blocked on Anchor Map, and Physical Validation Required sections.

- [ ] **Step 1: Mark implemented scope**

List the fixed timer, state machine, casualty progress events, outcome rules, HUD, debrief, debug controls, reset, and cleanup with exact source files.

- [ ] **Step 2: Mark anchor-blocked scope**

List map import/validation/alignment, five authored fire binding, casualty entity placement/tapping, exit transform/proximity, authored-fire persistence, and live route validation. State that none were approximated.

- [ ] **Step 3: Run complete verification**

Run:

```bash
DEVELOPER_DIR=/Users/kc/Downloads/Xcode-beta.app/Contents/Developer xcodebuild \
  -project respondR.xcodeproj -scheme respondR -configuration Debug \
  -destination 'generic/platform=visionOS Simulator' \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

DEVELOPER_DIR=/Users/kc/Downloads/Xcode-beta.app/Contents/Developer xcodebuild \
  -project respondR.xcodeproj -scheme respondR -configuration Debug \
  -destination 'generic/platform=visionOS' \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

DEVELOPER_DIR=/Users/kc/Downloads/Xcode-beta.app/Contents/Developer xcodebuild \
  -project respondR.xcodeproj -scheme respondR -configuration Debug \
  -destination 'generic/platform=visionOS Simulator' \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES analyze

plutil -lint respondR/Info.plist
git diff --check
```

- [ ] **Step 4: Review requirements and commit**

```bash
git add 'respondR/Resources/simulation (phase 2)/scenario_plan.md'
git commit -m 'docs: record scenario implementation status'
```

Physical Vision Pro validation remains blocked until the anchor map is available and signed hardware can run the complete route.
