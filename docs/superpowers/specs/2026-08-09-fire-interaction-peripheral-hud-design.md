# Phase 2 Fire Interaction and Peripheral HUD Design

Status: Approved on 9 August 2026

## Goal

Make Phase 2 begin with one deliberate fire-start interaction, spawn the extinguisher exactly five seconds after that successful start, make gaze-and-pinch pickup reliable, and move the smoothly following HUD out of the learner's central view.

## Existing problems

- The extinguisher countdown currently starts as soon as the immersive fire scene loads instead of when the fire begins.
- Extinguisher pickup waits for `SpatialTapGesture.onEnded`, while a simultaneous pinch handler sees the same gesture. Pickup therefore does not feel immediate and shares a path with fire ignition.
- Fire ignition uses the touched surface location, so scene pinches remain capable of creating more fires throughout the attempt.
- HUD and held-extinguisher transforms are updated by the 100 ms fire-simulation loop and are hard-snapped to each device pose. This produces visible 10 Hz stepping.
- The current combined HUD canvas keeps status surfaces too close to the centre of the learner's view.

## Approved interaction approach

Use a one-shot, state-gated scene-start gesture and entity-specific extinguisher gestures.

Alternatives considered:

1. A control-window `Start Fire` button would remove gesture ambiguity but break immersion.
2. Repeated scene-pinches could continue creating random fires, but this would retain the extinguisher conflict and allow accidental hazards.
3. The selected approach uses the first valid scene pinch once, then permanently disables scene fire creation for that attempt.

## Fire-start states

Each scenario attempt has two mapless fire-start states:

- `awaitingFireStart`: no fires have been placed and no extinguisher spawn task exists.
- `started`: five fires were placed successfully and the extinguisher countdown has begun.

While `awaitingFireStart`, the first pinch completed on a non-extinguisher scene entity requests five random fires. A pinch aimed at the extinguisher can never request fire placement.

The state changes to `started` only when all five fires are placed. After that transition, every further non-extinguisher scene pinch is ignored by the fire-start system. Fire spreading and extinguisher spraying continue through their existing systems.

Reset cancels any pending extinguisher spawn, removes fires and char, clears pickup and spray state, and returns to `awaitingFireStart`. The learner must perform a new start pinch for the next attempt.

## Random fire placement before the anchor map

The mapless placement source selects exactly five distinct occupied fire-grid cells around the current head position.

Candidate constraints:

- Horizontal distance from the learner: 1.5 to 4.0 metres.
- Vertical position: between 1.8 metres below and 0.35 metres below the tracked head position.
- Minimum centre-to-centre separation between selected fires: 0.8 metres.
- Cells already active, naturally burnt out, or manually extinguished are ineligible.

Candidates are shuffled and selected greedily until five separated cells are found. Selection is atomic: if fewer than five eligible cells exist, no fire is ignited, the state remains `awaitingFireStart`, and the learner is prompted to look around to scan more surfaces before pinching again.

This mapless random source is not a production fallback for a missing or invalid anchor map. When the map arrives, its five validated furniture-bound fire transforms replace the random-position request while the one-shot start event and extinguisher timing remain unchanged. Release remains blocked rather than silently using random placement when required map validation fails.

## Extinguisher timing and gesture routing

- The extinguisher asset may be preloaded and cached on immersive entry, but it is not added to the scene and no spawn-delay countdown begins.
- A successful five-fire start schedules the existing extinguisher controller once.
- The controller installs the preloaded extinguisher at the five-second boundary and never earlier. If an unavoidable asset-load or tracking delay remains, installation occurs as soon as both are ready and reports the delay instead of restarting the countdown.
- If head tracking is briefly unavailable after the five seconds, installation waits for the next valid tracked pose without restarting the delay.

When the extinguisher is available:

1. The learner looks at the extinguisher.
2. An active direct or indirect pinch targeted at any entity within the extinguisher hierarchy equips it immediately.
3. The pickup pinch is latched as a pickup interaction and cannot start spraying, even if the held pinch produces additional active updates.
4. Releasing the pickup pinch clears the latch.
5. A later targeted pinch-and-hold begins spraying; release or cancellation stops the cone and hiss immediately.

Once equipped, the extinguisher remains smoothly head-locked in the lower-right view using its existing true-to-size model, white cone, spatial hiss, and extinguishing behavior.

## Presentation loop and HUD placement

Fire simulation remains on its bounded 100 ms loop. Head-follow presentation moves to a separate approximately 60 Hz task so UI and held equipment are not coupled to fire tick frequency.

Tracked head transforms are converted to target transforms and stabilized with frame-rate-independent exponential interpolation. Translation and orientation use the same response window of approximately 120 ms. This removes stepping while keeping the surfaces responsive enough to follow deliberate head movement. Stabilization remains enabled with Reduce Motion because it is a comfort feature, not decorative animation.

Use separate RealityKit attachments so the centre contains no large transparent HUD canvas:

- Status attachment: health, challenge progress, and concise guidance at approximately `x = -0.45 m`, `y = +0.25 m`, `z = -1.15 m` in head space.
- Timer attachment: countdown at approximately `x = +0.45 m`, `y = +0.25 m`, `z = -1.15 m` in head space.
- Result attachment: centred at a comfortable forward distance after victory or defeat.

The status and timer retain native SwiftUI typography, semantic colours, accessibility labels, and visionOS `.glassBackgroundEffect()`. Decorative springs remain disabled when Reduce Motion is enabled.

## UI decision brief

- Surface type: Live spatial training HUD and deterministic debrief.
- Platform idiom: Branded native visionOS using SwiftUI and RealityKit.
- Product thesis: Keep essential responder information visible without covering the hazard environment.
- Density: Sparse and safety-oriented.
- Hierarchy: The physical scene is primary; health/challenges are peripheral left; time is peripheral right; result is central only after the attempt ends.
- Materials: Existing translucent native glass surfaces with semantic health and warning colours.
- Motion budget: Functional. Only stabilized head following and state feedback move.
- Reduced-motion behavior: Preserve stabilization; remove decorative transitions.
- Bans: No centre-blocking HUD canvas, particle-based extinguisher powder, repeated scene ignition, or fake release anchor fallback.

## Result screens

Victory and defeat retain their approved title, message, metrics, `Try Again`, and `End Training` controls. Both also display this visually secondary instruction:

> Press the Digital Crown to exit.

The instruction receives an accessibility label and does not replace the explicit result actions.

## Error and lifecycle behavior

- Missing head pose during fire start: do not place fires or start the extinguisher countdown; show a tracking prompt.
- Insufficient eligible scanned cells: place no partial fire set and prompt the learner to scan more.
- Extinguisher load failure: preserve the active scenario and show the existing controller error.
- Scenario victory, defeat, reset, Phase 2 exit, or immersive disappearance stops the presentation task, pending spawn, spray cone, and hiss.
- Fire and damage updates remain disabled outside the Active scenario state.

## Validation

No automated scenario tests will be added, per the approved project scope.

Local validation:

- Strict Debug visionOS Simulator build.
- Strict Release visionOS Simulator build.
- Strict generic visionOS device build with local code signing disabled.
- Xcode static analysis.
- `Info.plist`, bundle-resource, and `git diff --check` validation.

Physical Vision Pro validation:

- The extinguisher is absent before fire start.
- One start pinch creates exactly five separated fires and no later pinch creates more.
- The extinguisher becomes available five seconds after successful fire placement.
- Gaze and pinch equips immediately; the pickup pinch never sprays.
- A later pinch-and-hold sprays and release stops the cone and hiss.
- The held extinguisher remains stable in the lower-right view.
- Health and challenges remain in the upper-left periphery, the timer remains upper-right, and the centre stays clear.
- Head-following appears smooth during slow and quick head turns without uncomfortable lag.
- Victory and defeat both show the Digital Crown instruction.

The simulator and compiler cannot establish live World Tracking, scene reconstruction, gaze targeting, comfort, or Digital Crown behavior. Those remain physical-device acceptance gates.

## Non-goals

- Implementing or fabricating the missing anchor map.
- Anchoring fires to temporary furniture guesses.
- Allowing configurable fire count, distance, or extinguisher delay.
- Changing the five-minute scenario timer or casualty/exit victory requirements.
- Requiring all fires to be extinguished for victory.
- Adding automated scenario tests.
