# Phase 2 Fire Training Scenario Plan

Scenario duration: Fixed at 5 minutes

## 0. Implementation status — 9 August 2026

### Implemented now without the anchor map

- Fixed `05:00` scenario timer and Preparing, Active, Victory, and Defeat states.
- Registration of stable casualty IDs, idempotent rescue events, and `X/N` progress.
- Victory when every registered casualty is rescued and the exit event occurs with time remaining.
- Defeat on timeout, zero health, or an exit event with casualties left behind.
- Fire is excluded from the victory condition.
- One deliberate non-extinguisher scene pinch atomically starts exactly five separated random fires around the learner in Debug mapless mode. Later scene pinches cannot create more fires in that attempt.
- Extinguisher asset preloading without scene installation, followed by a five-second spawn countdown that begins only after all five fires start successfully.
- A single `gabe.usdz` casualty in Debug mapless training. His five-second countdown begins only after the extinguisher actually appears; he then waits for a valid scanned-floor point 6.5–7.5 metres from the learner rather than floating in head space.
- One gaze-targeted pinch rescues Gabe exactly once, removes him from the world location immediately, and shows the same model at uniform scale `0.2` in the lower-left view to represent carrying him without an inventory screen.
- Gaze-and-pinch extinguisher pickup with a collision-only target twice the normalized model bounds and a pickup latch, so the pickup pinch cannot also spray. A later targeted pinch-and-hold shows a brighter double-sided white cone from the hose nozzle and plays the hiss until release or cancellation.
- Active fire visuals grow continuously from `1x` to approximately `4x` over the burning phase before natural burnout creates char. Manual extinguishing still removes fire immediately without char.
- Split peripheral HUD attachments: health, challenge progress, and concise guidance in the upper-left; fixed countdown in the upper-right; no centre-spanning HUD canvas.
- An approximately 60 Hz stabilized presentation loop for the head-following HUD and lower-right equipped extinguisher, independent from the bounded 10 Hz fire simulation.
- Interactive spatial victory/defeat debrief with completion time, casualty result, Try Again, End Training, and the exact instruction `Press the Digital Crown to exit.`
- The main volumetric window is dismissed only after the immersive space opens and is reopened when immersion ends, preventing an otherwise empty floating volume from remaining beside Phase 2.
- Complete reset/end event paths for timer, health exposure, outcome, one-shot fire start, fire/char rendering, delayed extinguisher and Gabe spawns, world/carried Gabe, pickup latch, spray cone, and hiss.
- Debug-only event controls for Reach Exit, Expire Timer, and Deplete Health. Casualty progress must use the spatial Gabe interaction.
- Release behavior that remains in Preparing and reports the missing anchor map instead of inventing spatial content.

Primary implementation files:

- `simulation/ScenarioSession.swift`
- `simulation/AppModel.swift`
- `simulation/HUDView.swift`
- `simulation/HeadFollowSmoother.swift`
- `simulation/ScenarioResultView.swift`
- `simulation/ImmersiveMeshView.swift`
- `simulation/ControlWindowView.swift`

### Debug behavior while the map is unavailable

Debug builds register the single casualty ID `mapless-gabe`. After scene reconstruction has supplied enough eligible cells, the first scene pinch creates five mapless random fires 1.5–4.0 metres around the learner. The extinguisher appears five seconds later; another five seconds after its actual appearance, Gabe spawns at authored scale on a suitable scanned floor 6.5–7.5 metres away. This does not create a temporary exit, authored furniture-bound fire, anchor, or route and is never a Release fallback.

### Unable to implement until the anchor map is supplied

- Importing and validating the real anchor map and its training-zone alignment reference.
- Replacing the Debug mapless random fire source with the five authored furniture-bound fire identifiers and real transforms.
- Making authored blocking fires persist at those real locations until extinguished.
- Replacing Debug scanned-floor Gabe placement with the real map casualty transform and alignment validation.
- Binding the real Gabe casualty identifier to his authored map transform.
- Binding the single exit-door identifier to its real transform and proximity dwell zone.
- Validating the one-shot fire-start event against the map adapter instead of the current Debug random placement source.
- Validating occlusion, reachability, alignment, collision, route safety, and exit accuracy.
- Completing the required physical Vision Pro end-to-end scenario run.

The Debug-only Gabe and random fires deliberately exercise interaction and lifecycle behavior without pretending to validate the authored route. Release still receives no head-relative or random fallback, and no temporary exit exists.

### Current local verification

- Strict Debug and Release visionOS Simulator builds pass with Swift warnings treated as errors.
- A strict generic visionOS device build passes with code signing disabled for local compilation.
- Xcode static analysis passes for the Debug visionOS Simulator target.
- `Info.plist`, whitespace, exact Digital Crown copy, call-site, and bundle-resource checks pass. The Release app contains `Fire_Extinguisher.usdz`, `gabe.usdz`, and this plan.
- Release binary inspection confirms that the Debug event-control labels are absent.

The interactive mission flow has not been marked as physically validated. Scene reconstruction is unavailable in the simulator, and the final spatial route cannot be run until the anchor map is supplied and the app is exercised on a physical Apple Vision Pro.

## 1. Scenario purpose

Phase 2 is a timed fire-response training scenario. The learner must move through the mapped training zone, use the fire extinguisher where necessary, rescue every casualty, find the exit door, and escape before the five-minute timer expires.

The scenario should remain simple to understand:

1. Pinch a scanned surface once to start the fire event.
2. Look at the extinguisher when it appears and pinch to equip it.
3. Extinguish fires that prevent safe progress.
4. Look at Gabe and pinch once to rescue and carry him.
5. Find and reach the exit before time runs out.

Extinguishing every fire is not a victory requirement. Fire is an environmental hazard and route obstacle, not a checklist objective.

## 2. Approved scope decisions

- The timer is always `05:00`. There is no duration setting or scenario configuration UI.
- Victory requires every casualty to be rescued and the learner to reach the exit while time remains.
- Defeat occurs when time expires, health reaches zero, or the learner reaches the exit without rescuing every casualty.
- Fires do not appear as a completion counter and do not need to be fully extinguished.
- Casualties are rescued with one gaze-targeted pinch.
- Picking up Gabe records the rescue, removes him from danger immediately, and displays him at 20% scale in the lower-left view to show he is being carried. There is no casualty inventory screen.
- Debug mapless training may place the single Gabe casualty on a scanned floor 6.5–7.5 metres away. No temporary casualty or exit positions are added to Release.
- Debug-only controls may trigger exit, timeout, and health events before the anchor map arrives. They are excluded from release builds; casualty rescue is exercised through Gabe himself.
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

### Selected for Debug only: scanned-floor Gabe

The single Debug Gabe validates asset loading, gaze targeting, idempotent rescue, disappearance, carried presentation, and reset cleanup. His scanned-floor placement does not validate the real map, alignment, route, or exit and is never used in Release.

### Rejected: temporary Release spatial fallbacks and exit

Random or head-relative production placements would hide missing map/alignment failures and could create unsafe or misleading training geometry. Release therefore remains blocked, and no temporary exit is created.

### Rejected: waiting for the map before building any scenario functionality

This would unnecessarily delay the timer, objective HUD, result screens, mission state, reset behavior, and debug validation. Those features are independent of map transforms and can be completed first.

## 4. UX decision brief

- Job: Rescue every casualty and reach the exit within five minutes.
- User mode: Learner completing a guided fire-response exercise.
- Frequency and risk: Repeated training exercise with physical movement and safety-sensitive feedback.
- Pattern: Live mission HUD followed by a deterministic debrief screen.
- Primary action: Move through the scenario and rescue casualties.
- Supporting action: Extinguish fires that obstruct safe progress.
- Core path: Enter Phase 2 → start five fires once → wait five seconds → gaze-and-pinch extinguisher → wait five seconds for Gabe → manage hazards → rescue and carry Gabe → reach exit → receive debrief.
- Recovery path: Defeat screen → Try Again → complete scenario reset → restart at `05:00`.
- Required states: Preparing, active, victory, defeat, map error, reset in progress.
- Handoff constraint: The anchor map supplies spatial transforms only; it must not own timer, objective, or outcome rules.

## 5. Scenario content contract

The final anchor map must provide stable identifiers and transforms for:

- Five authored fire locations.
- Exactly one required casualty location for Gabe.
- Exactly one exit-door location.
- The authored training-zone alignment reference used to place these entities correctly.

Scenario start must be blocked if the map is missing, alignment is invalid, Gabe is missing or duplicated, or the exit is missing or duplicated. The app must show a clear error instead of silently placing missing content near the learner.

The mission state still registers its objective by stable identifier, but this authored scenario supplies exactly one required casualty: Gabe.

## 6. Scenario states

### Preparing

- The app loads and validates the anchor map.
- The timer is visible at `05:00` but does not count down.
- Fire damage, fire spread, casualty interaction, and exit detection are disabled.
- If preparation fails, the scenario remains blocked with a clear recovery message.

### Active

- The timer counts down from `05:00` using real elapsed time.
- Health and fire-proximity damage operate normally.
- The first valid fire-start pinch creates five fires once and starts the extinguisher's five-second spawn delay.
- An active pinch targeted at the available extinguisher equips it immediately. The pickup pinch cannot spray; a later targeted pinch-and-hold controls the cone and hiss.
- In Debug, the extinguisher's actual appearance starts Gabe's five-second delay. Gabe then appears only after a valid scanned-floor point is available 6.5–7.5 metres away.
- One gaze-targeted pinch rescues Gabe once, removes him from his floor position immediately, and moves the 20%-scale carried presentation to the lower-left view.
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

- Existing fires, char, pending/world/carried casualty state, exit state, outcome state, health exposure, timer state, extinguisher state, spray cone, and hiss are cleared.
- The same validated anchor map is reused if it is still available and aligned.
- The scenario returns to Active with full health, all casualties restored, and the timer reset to `05:00`.
- Fire start returns to `awaitingFireStart`; no extinguisher countdown exists until a new successful five-fire start pinch.

## 7. Fixed five-minute timer

- The Phase 2 scenario duration is exactly 300 seconds.
- The HUD begins at `05:00` when the scenario enters Active.
- Loading, map validation, and permission handling do not consume scenario time.
- The timer uses elapsed time rather than assuming a fixed update rate.
- At `00:00`, defeat is resolved immediately and only once.
- Reaching the exit at the same update in which time expires is a defeat. Victory requires positive time remaining.
- The timer freezes on victory, defeat, reset, or exit from Phase 2.

## 8. Fire behavior

### Current Debug mapless behavior

- The first valid non-extinguisher scene pinch selects exactly five occupied grid cells 1.5–4.0 metres from the learner, 1.8–0.35 metres below head height, and at least 0.8 metres apart.
- Placement is atomic. If five eligible cells are unavailable, no fire starts, no extinguisher countdown begins, and the learner is prompted to scan more surfaces.
- After successful placement, later scene pinches are ignored by the fire-start system until reset.
- Igniting fire begins at `1x`. During the natural burning phase its visual scale grows linearly to approximately `4x` before burnout.
- This random source is Debug mapless training only and must never become a Release fallback for a missing or invalid anchor map.

### Final anchor-map behavior

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

- The learner looks at the casualty and pinches once to pick them up.
- The first valid targeted pinch changes the casualty to Rescued.
- Repeated pinches cannot increment progress more than once.
- The casualty is removed from the hazard position immediately after rescue.
- A 20%-scale carried representation appears in the lower-left view and follows the stabilized head pose.
- The objective HUD updates immediately.
- The extinguisher remains equipped; casualty rescue does not introduce an inventory or equipment conflict.

Before the anchor map arrives, Debug uses `gabe.usdz` at authored world scale on a suitable scanned-floor point 6.5–7.5 metres away. Its fixed five-second delay begins after the extinguisher actually spawns. This placement validates the rescue interaction but not map alignment, route safety, or the final authored casualty location. Release remains blocked until those real spatial inputs exist.

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

The head-following HUD uses separate peripheral status surfaces:

- Upper-left: health, casualty progress shown as `CASUALTIES 0/N`, mission guidance, and contextual extinguisher guidance.
- Upper-right: fixed five-minute countdown.
- Centre: no status canvas; it is reserved for the physical scene and, after an outcome, the result surface.
- The attachments and equipped extinguisher follow a stabilized approximately 60 Hz head pose rather than stepping with the 10 Hz fire simulation.

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

Both outcomes also show:

> Press the Digital Crown to exit.

## 13. Debug-only validation before the anchor map

The existing control window may expose the following actions only in Debug builds:

- `Reach Exit`
- `Expire Timer`
- `Deplete Health`
- `Reset Scenario`

These controls exercise production outcome and reset events and are not release-visible. Casualty rescue is intentionally absent from the controls so the mission state cannot diverge from spatial Gabe.

This allows the five-minute timer, victory, each defeat reason, debrief, and reset behavior to be reviewed before exit integration. Spatial Gabe exercises objective progress and rescue cleanup directly.

## 14. Work that can proceed before the anchor map

1. Map-independent scenario session state and fixed 300-second timer. Implemented.
2. Casualty objective registration and idempotent rescue events. Implemented.
3. Exit outcome evaluation, health defeat, and timer defeat. Implemented.
4. One-shot atomic five-fire Debug placement. Implemented.
5. Post-fire extinguisher delay, gaze pickup latch, cone, hiss, and cleanup. Implemented.
6. Delayed scanned-floor Gabe spawn, gaze rescue, 20%-scale carried presentation, and cleanup. Implemented for Debug mapless training.
7. `1x`-to-`4x` active fire growth before natural burnout. Implemented.
8. Peripheral stabilized HUD and victory/defeat debrief. Implemented.
9. Main-window dismissal during immersion and reopen on exit. Implemented.
10. Try Again, End Training, Digital Crown guidance, and Debug event controls. Implemented.
11. Strict local build, analysis, and bundle validation. Required before handoff.

## 15. Work held until the anchor map arrives

1. Import and validate the real map and its alignment reference.
2. Bind the five fire identifiers to their authored transforms.
3. Replace Debug scanned-floor Gabe placement with every real casualty identifier and authored transform.
4. Bind the single exit identifier to its real door transform and proximity zone.
5. Replace the Debug random fire source with map-authored furniture fire startup while retaining the one-shot event and post-start extinguisher delay.
6. Validate occlusion, reachability, collision, comfort, and route safety on physical Vision Pro hardware.

## 16. Manual validation plan

No automated scenario tests are required. The completed scenario must pass the following manual checks.

### Before anchor integration

- Scenario begins at exactly `05:00` and counts down accurately.
- The extinguisher is absent before fire start.
- One scene pinch creates exactly five separated fires; later scene pinches create none.
- The extinguisher appears five seconds after successful fire placement, never five seconds after immersive entry.
- Gabe's countdown starts only when the extinguisher actually appears. Gabe appears about five seconds later if a suitable scanned floor is available 6.5–7.5 metres away; otherwise the app waits and asks the learner to scan more floor rather than floating him.
- Gaze-and-pinch equips immediately through the doubled pickup target, and that pickup pinch never sprays.
- A later targeted pinch-and-hold shows the brighter white cone directly from the hose nozzle and plays the hiss; release or cancellation removes both immediately.
- One gaze-targeted pinch on Gabe records the single rescue, removes the world placement immediately, and shows him at 20% scale in the lower-left view without opening an inventory.
- Repeated Gabe pinches cannot double-count the rescue.
- Active fire visuals grow from 1x to approximately 4x before natural burnout and char.
- The held extinguisher stays lower-right, the status HUD stays upper-left, the timer stays upper-right, and all follow head movement smoothly.
- The main volumetric window disappears after immersive entry, no blank volume remains, and the main window reopens when immersion ends.
- Reaching the exit with all casualties rescued and time remaining shows Victory.
- Reaching the exit with any casualty remaining shows Defeat.
- Timer expiry shows Defeat once and freezes the scenario.
- Zero health shows Defeat once and freezes the scenario.
- Fire state is never used as a victory requirement.
- Try Again restores health, timer, and casualty progress; it clears fires, world/carried Gabe, and the extinguisher, then requires a new successful start pinch before beginning another extinguisher delay and subsequent Gabe delay.
- End Training stops the timer, fire updates, spray visual, and hiss.
- Victory and defeat both show `Press the Digital Crown to exit.`

### After anchor integration on physical Vision Pro

- The map aligns correctly with the real training zone before the scenario can start.
- All five fires appear at the authored locations.
- Every casualty appears at its authored location and can be gaze-targeted and pinched reliably.
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

- A validated anchor map supplies five fires, exactly one Gabe casualty, and exactly one exit.
- The learner receives clear mission instructions and a fixed five-minute countdown.
- Every casualty can be rescued exactly once with a gaze-targeted pinch.
- The learner can use the existing extinguisher to clear necessary fires.
- Victory occurs only after all casualties are rescued and the exit is reached with time remaining.
- Defeat occurs on timeout, zero health, or reaching the exit with casualties left behind.
- Victory and defeat screens show the approved copy and correct results.
- Both result screens show `Press the Digital Crown to exit.`
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
- Multiple exits or exit selection.
- Scoring, grades, leaderboards, or performance analytics beyond the result summary.
- Automated scenario tests.
- Anchor-map authoring or alignment work before the real map is supplied.
