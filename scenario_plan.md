# Phase 2 Fire Training Scenario Plan

Status: Draft for review

Platform: Apple Vision Pro, visionOS 27

Scenario duration: Fixed at 5 minutes

## 1. Scenario purpose

Phase 2 is a timed fire-response training scenario. The learner must move through the mapped training zone, use the fire extinguisher where necessary, rescue every casualty, find the exit door, and escape before the five-minute timer expires.

The scenario should remain simple to understand:

1. Pick up the fire extinguisher.
2. Extinguish fires that prevent safe progress.
3. Pick up every casualty.
4. Find and reach the exit before time runs out.

Extinguishing every fire is not a victory requirement. Fire is an environmental hazard and route obstacle, not a checklist objective.

## 2. Approved scope decisions

- The timer is always `05:00`. There is no duration setting or scenario configuration UI.
- Victory requires every casualty to be rescued and the learner to reach the exit while time remains.
- Defeat occurs when time expires, health reaches zero, or the learner reaches the exit without rescuing every casualty.
- Fires do not appear as a completion counter and do not need to be fully extinguished.
- Casualties are rescued by tapping them once.
- Picking up a casualty records the rescue and removes the casualty from danger. There is no casualty inventory screen or persistent carried-body model in this scope.
- No temporary casualty positions or temporary exit positions will be added to the production immersive scene.
- Debug-only controls may trigger mission events before the anchor map arrives. These controls do not contain spatial positions and are excluded from release builds.
- No automated test suite is required for this scenario. Build validation and physical Vision Pro end-to-end checks are still required.
- The anchor map and all anchor-bound placement work remain on hold until the real map is supplied.

## 3. Selected implementation approach

### Selected: anchor-independent mission state with an anchor adapter

Mission rules, HUD progress, timer behavior, result screens, and reset behavior will depend on stable scenario events rather than RealityKit transforms:

- `scenarioStarted`
- `casualtyRescued(casualtyID)`
- `exitReached`
- `healthDepleted`
- `timeExpired`
- `scenarioReset`

When the anchor map arrives, a small anchor adapter will translate real anchored interactions into these events. The mission state does not need to know where an entity is placed.

### Rejected: temporary spatial casualties and exit

Temporary scene positions would provide limited value because they would not validate the real map, alignment, route, reachability, or physical comfort. They would also introduce scene code that must be removed or carefully separated later.

### Rejected: waiting for the map before building any scenario functionality

This would unnecessarily delay the timer, objective HUD, result screens, mission state, reset behavior, and debug validation. Those features are independent of map transforms and can be completed first.

## 4. UX decision brief

- Job: Rescue every casualty and reach the exit within five minutes.
- User mode: Learner completing a guided fire-response exercise.
- Frequency and risk: Repeated training exercise with physical movement and safety-sensitive feedback.
- Pattern: Live mission HUD followed by a deterministic debrief screen.
- Primary action: Move through the scenario and rescue casualties.
- Supporting action: Extinguish fires that obstruct safe progress.
- Core path: Enter Phase 2 → pick up extinguisher → manage hazards → rescue casualties → reach exit → receive debrief.
- Recovery path: Defeat screen → Try Again → complete scenario reset → restart at `05:00`.
- Required states: Preparing, active, victory, defeat, map error, reset in progress.
- Handoff constraint: The anchor map supplies spatial transforms only; it must not own timer, objective, or outcome rules.

## 5. Scenario content contract

The final anchor map must provide stable identifiers and transforms for:

- Five authored fire locations.
- Every casualty included in the scenario, with at least one casualty required.
- Exactly one exit-door location.
- The authored training-zone alignment reference used to place these entities correctly.

Scenario start must be blocked if the map is missing, alignment is invalid, there are no casualties, any required casualty identifier is duplicated, or the exit is missing or duplicated. The app must show a clear error instead of silently placing missing content near the learner.

The casualty count is not hardcoded in the mission logic. At scenario start, every valid casualty identifier supplied by the anchor map becomes a required rescue objective.

## 6. Scenario states

### Preparing

- The app loads and validates the anchor map.
- The timer is visible at `05:00` but does not count down.
- Fire damage, fire spread, casualty interaction, and exit detection are disabled.
- If preparation fails, the scenario remains blocked with a clear recovery message.

### Active

- The timer counts down from `05:00` using real elapsed time.
- Health and fire-proximity damage operate normally.
- The extinguisher follows its existing five-second spawn, pickup, held-pinch spray, hiss, and cleanup behavior.
- Casualties can be rescued once each.
- Exit proximity can resolve the attempt.

### Victory

- Entered only when the learner reaches the exit with every casualty rescued and `timeRemaining > 0`.
- The timer, fire simulation, damage, exit detection, casualty interaction, extinguisher spray cone, and hiss stop immediately.
- A centered debrief screen is placed comfortably in front of the learner.

### Defeat

- Entered immediately when the timer reaches zero, health reaches zero, or the learner reaches the exit with casualties still unrescued.
- The same simulation and interaction systems stop immediately.
- The debrief records a reason: `timeExpired`, `healthDepleted`, or `casualtiesLeftBehind`.

### Resetting

- Existing fires, char, casualty state, exit state, outcome state, health exposure, timer state, extinguisher state, spray cone, and hiss are cleared.
- The same validated anchor map is reused if it is still available and aligned.
- The scenario returns to Active with full health, all casualties restored, and the timer reset to `05:00`.
- The extinguisher begins a fresh five-second spawn cycle.

## 7. Fixed five-minute timer

- The Phase 2 scenario duration is exactly 300 seconds.
- The HUD begins at `05:00` when the scenario enters Active.
- Loading, map validation, and permission handling do not consume scenario time.
- The timer uses elapsed time rather than assuming a fixed update rate.
- At `00:00`, defeat is resolved immediately and only once.
- Reaching the exit at the same update in which time expires is a defeat. Victory requires positive time remaining.
- The timer freezes on victory, defeat, reset, or exit from Phase 2.

## 8. Fire behavior

- The five authored fires spawn only at their validated map anchors.
- Authored blocking fires remain active until extinguished or until the scenario ends, so waiting does not remove the training obstacle.
- Fire may continue using the existing bounded spread behavior.
- Spread fire cells may follow the existing natural lifecycle and leave char when they burn out.
- Manually extinguished fire disappears immediately, stops spreading, stops damaging the learner, cannot reignite during the session, and leaves no char.
- Fire count is not shown as an objective and is never checked by the victory condition.
- The learner may leave non-blocking fires active if every casualty can still be rescued and the exit can be reached safely.

## 9. Casualty rescue behavior

Each casualty has a stable identifier and one of two states:

- `waitingForRescue`
- `rescued`

Interaction rules:

- The learner taps the casualty to pick them up.
- The first valid tap changes the casualty to Rescued.
- Repeated taps cannot increment progress more than once.
- The casualty is removed from its hazard position after rescue.
- A brief confirmation sound and visual acknowledgement are shown.
- The objective HUD updates immediately.
- The extinguisher remains equipped; casualty rescue does not introduce an inventory or equipment conflict.

The rescue interaction is connected to the real casualty entity only after the anchor map arrives. Before then, debug-only controls may call the same rescue event using known casualty identifiers without spawning a fake spatial casualty.

## 10. Exit behavior

- The exit uses exactly one validated exit-door anchor.
- A small proximity zone is attached to the real exit location.
- The exit is reached when the tracked head position remains inside the zone for a short dwell, preventing an accidental single-frame trigger.
- Exit detection is active only while the scenario is Active.
- If every casualty is rescued and time remains, reaching the exit produces Victory.
- If any casualty remains, reaching the exit produces Defeat with reason `casualtiesLeftBehind`.
- Fire status does not affect exit evaluation.

No temporary exit entity or proximity zone will be added before the real anchor map is available. A debug-only `Reach Exit` action may exercise the same outcome logic without a transform.

## 11. HUD and in-scenario guidance

The existing head-following HUD remains the main status surface:

- Top-left: health.
- Below health: casualty progress, shown as `CASUALTIES 0/N`.
- Bottom-right: fixed five-minute countdown.
- Existing extinguisher pickup and spray guidance remains available when relevant.

Mission guidance should remain concise:

- At scenario start: `Rescue every casualty and reach the exit before time runs out.`
- While casualties remain: `Casualties remaining: N`
- After the final rescue: `All casualties rescued. Find the exit.`

The HUD does not show a fire completion objective. The environment and fire damage communicate which hazards require action.

## 12. Victory and defeat screens

The result surface appears in front of the learner and takes focus while the immersive scene is paused.

### Victory

Title:

> Congratulations!

Message:

> You managed to rescue the casualties and escaped successfully!

Supporting results:

- Completion time.
- Casualties rescued: `N/N`.

### Defeat

Title:

> Try again!

Message:

> Remember to rescue the casualty and escape on time to save everybody!

Supporting reason:

- `Time ran out.`
- `Your health reached zero.`
- `A casualty was left behind.` or `Casualties were left behind.`, selected from the remaining count.

Supporting results:

- Time used or `05:00` when time expired.
- Casualties rescued: `X/N`.

### Result actions

- Primary: `Try Again`
- Secondary: `End Training`

Try Again performs a complete scenario reset. End Training stops all scenario systems, dismisses Phase 2 safely, and returns to the existing phase-selection flow.

## 13. Debug-only validation before the anchor map

The existing control window may expose the following actions only in Debug builds:

- `Rescue Next Casualty`
- `Reach Exit`
- `Expire Timer`
- `Deplete Health`
- `Reset Scenario`

These controls exercise production mission events and result screens. They do not create RealityKit entities, transforms, anchor fallbacks, or release-visible UI.

This allows the five-minute timer, objective progress, victory, each defeat reason, debrief, and reset behavior to be reviewed before spatial integration without creating throwaway placement code.

## 14. Work that can proceed before the anchor map

1. Add the map-independent scenario session state and fixed 300-second timer.
2. Add casualty objective registration and idempotent rescue events.
3. Add exit outcome evaluation.
4. Connect zero health and timer expiry to Defeat.
5. Add casualty progress and mission guidance to the HUD.
6. Add victory and defeat debrief screens.
7. Add Try Again and End Training cleanup behavior.
8. Add Debug-only mission-event controls.
9. Build for generic visionOS Simulator and generic visionOS device, then run Xcode analysis.

## 15. Work held until the anchor map arrives

1. Import and validate the real map and its alignment reference.
2. Bind the five fire identifiers to their authored transforms.
3. Bind every casualty identifier to its real transform and casualty entity.
4. Bind the single exit identifier to its real door transform and proximity zone.
5. Replace free-form fire ignition in scenario mode with map-authored fire startup.
6. Validate occlusion, reachability, collision, comfort, and route safety on physical Vision Pro hardware.

## 16. Manual validation plan

No automated scenario tests are required. The completed scenario must pass the following manual checks.

### Before anchor integration

- Scenario begins at exactly `05:00` and counts down accurately.
- Rescue events update progress once per casualty identifier.
- Repeating the same rescue event does not double-count.
- Reaching the exit with all casualties rescued and time remaining shows Victory.
- Reaching the exit with any casualty remaining shows Defeat.
- Timer expiry shows Defeat once and freezes the scenario.
- Zero health shows Defeat once and freezes the scenario.
- Fire state is never used as a victory requirement.
- Try Again restores health, timer, casualties, fires, extinguisher spawn, and Active state.
- End Training stops the timer, fire updates, spray visual, and hiss.

### After anchor integration on physical Vision Pro

- The map aligns correctly with the real training zone before the scenario can start.
- All five fires appear at the authored locations.
- Every casualty appears at its authored location and can be tapped reliably.
- Each rescued casualty disappears from danger and updates the HUD once.
- The exit triggers only at the real door and does not trigger from nearby unrelated positions.
- The learner can complete the intended route without unsafe real-world movement.
- Blocking fires remain meaningful until extinguished.
- Extinguished fires immediately stop damage and never leave char.
- Naturally expired spread fires continue to leave char.
- Victory is achievable in under five minutes when all casualties are rescued.
- Each defeat condition behaves correctly during a complete physical run.
- Reset produces a clean second attempt without stale entities, audio, char, progress, or timers.

## 17. Acceptance criteria

The scenario is complete when:

- A validated anchor map supplies five fires, at least one casualty, and exactly one exit.
- The learner receives clear mission instructions and a fixed five-minute countdown.
- Every casualty can be rescued exactly once by tapping.
- The learner can use the existing extinguisher to clear necessary fires.
- Victory occurs only after all casualties are rescued and the exit is reached with time remaining.
- Defeat occurs on timeout, zero health, or reaching the exit with casualties left behind.
- Victory and defeat screens show the approved copy and correct results.
- Try Again fully resets the scenario and End Training fully cleans it up.
- Fire completion is never treated as a victory requirement.
- Missing or invalid spatial data blocks startup with a clear error and never falls back to a fake placement.
- Generic simulator/device builds and Xcode analysis pass.
- The complete scenario passes the physical Vision Pro manual validation plan.

## 18. Explicit non-goals

- Configurable scenario duration.
- Requiring every fire to be extinguished.
- A fire objective counter or fire score.
- Temporary production casualty or exit positions.
- Casualty inventory management.
- A persistent carried-casualty body model.
- Multiple exits or exit selection.
- Scoring, grades, leaderboards, or performance analytics beyond the result summary.
- Automated scenario tests.
- Anchor-map authoring or alignment work before the real map is supplied.
