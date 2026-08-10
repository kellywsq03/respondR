# Phase 2 Casualty, Extinguisher Reliability, and Fire Growth Design

Status: Approved on 9 August 2026

## Goal

Add one rescuable `gabe.usdz` casualty to the mapless Phase 2 scenario, make the extinguisher substantially easier to target and align its visible spray with the actual hose nozzle, grow each fire from 1x to approximately 4x over its natural lifetime, and remove the empty volumetric window that can remain visible beside the immersive scene.

## Existing causes

- The extinguisher currently generates collision from its narrow rendered mesh. Indirect gaze targeting therefore requires the learner to hit the exact silhouette, while direct targeting has no expanded interaction volume.
- The cone apex is a hard-coded head-relative offset. It is not parented to the extinguisher and does not use the hose nozzle shown by the asset.
- The cone uses a lightly opaque lit material and one triangle winding, which makes it difficult to see from some viewing directions.
- Fire rendering receives only active positions. It has no lifetime progress with which to scale individual emitters.
- Debug currently registers two non-spatial casualty identifiers even though the approved scenario now has one physical casualty.
- The app has one persistent volumetric `WindowGroup`. During Phase 2, its content is a floating RealityView attachment and the volume remains open beside the immersive space, which can present as an empty window.

## Selected architecture

Use three focused extensions rather than adding more state directly to `ImmersiveMeshView`:

1. A `CasualtyController` owns Gabe's asset, delayed installation, targeting, rescue, carried representation, and cleanup.
2. `FireExtinguisherController` owns an expanded interaction proxy and a model-local hose-nozzle anchor.
3. `FireSimulation` exposes stable fire visual samples containing position and growth scale; `FireRenderer` applies those samples to its existing fixed pool.

`ImmersiveMeshView` remains the orchestration boundary. It wires the extinguisher's actual spawn event to the casualty delay, routes spatial pinches by entity hierarchy, updates carried Gabe during the existing presentation loop, and resets all controllers together.

Alternatives rejected:

- Keeping all casualty state inside `ImmersiveMeshView` would be quicker but would further combine asset loading, placement, gesture routing, mission state, and rendering in one view.
- Building a generic anchor-entity framework now would be premature before the real map contract arrives.
- Placing Gabe at a fixed head-relative height would be a floating fallback and would not respect the scanned floor.

## Casualty lifecycle

- `gabe.usdz` is the scenario's single required casualty with stable ID `mapless-gabe`.
- The asset may preload when the immersive scene starts, but it is not visible yet.
- `FireExtinguisherController` reports installation through `onDidSpawn` only after the true-size extinguisher has been added to the scene.
- That callback starts one five-second casualty delay. The delay is not based on fire start time or the extinguisher's scheduled time.
- At the boundary, the controller requests a random upward-facing scanned floor position with horizontal distance 6.5–7.5 metres from the current tracked head position and a plausible floor-height offset.
- If tracking or a suitable floor surface is unavailable, the controller waits for updated scan data. It never places Gabe in mid-air or silently uses a head-relative fallback.
- The authored Gabe asset is already approximately human length, so its world representation retains uniform scale 1.0. It is centred on the selected floor pose and receives collision, `InputTargetComponent`, and hover feedback.
- A direct or indirect pinch targeted anywhere in Gabe's entity hierarchy requests `AppModel.recordCasualtyRescue(casualtyID: "mapless-gabe")`.
- The first accepted rescue removes the world-space interaction target immediately, changes the same visual representation to uniform scale 0.2, and places it at approximately `x = -0.32 m`, `y = -0.35 m`, `z = -0.65 m` in stabilized head space.
- The 20%-scale carried representation remains lower-left while the scenario is Active. It has no collision or input targeting and cannot be rescued twice.
- Victory, defeat, reset, Phase 2 exit, immersive disappearance, or full cancellation removes world and carried casualty state and cancels pending load/spawn work.

The mapless placement is a current Debug training source, not a Release fallback. Release remains in Preparing without the real anchor map. The future map adapter will replace only the floor-position source while retaining the casualty ID, rescue event, carried state, and cleanup lifecycle.

## Extinguisher reliability and nozzle alignment

- Keep the current 0.55-metre normalized visual size.
- After centring the asset, add an invisible collision-only proxy whose X, Y, and Z dimensions are twice the normalized model bounds. The proxy receives `InputTargetComponent` and hover feedback and belongs to the extinguisher hierarchy, so existing `contains(_:)` routing accepts it.
- Keep generated visual collision on the model, but use the expanded proxy to make coarse gaze/direct targeting forgiving.
- Add a model-local nozzle anchor at the visible black hose tip: near the lower-left and slightly forward of the centred extinguisher bounds.
- Parent the cone entity to that anchor. During equipped presentation, derive both the rendered cone transform and `SprayCone` apex/direction from the nozzle anchor's world transform.
- Preserve head-forward aiming, but originate it at the hose tip rather than a separate guessed head offset.
- Make the cone double-sided by emitting both triangle windings and use an unlit white material at approximately 0.45 opacity. No powder particles are added.
- Pickup pinch latching, hiss lifecycle, two-metre range, 17.5-degree half-angle, no-char extinguishing, and lower-right equipped placement remain unchanged.

## Fire growth

- Extend each runtime fire with enough timing data to calculate its visual growth without changing spread, damage, extinguishing, or burnout rules.
- Igniting cells render at scale 1.0.
- Burning cells interpolate linearly from scale 1.0 at the beginning of the burning phase to scale 4.0 at natural burnout.
- `FireSimulation.activeVisuals(now:)` returns stable, coordinate-sorted samples containing world position and scale. Stable ordering prevents pooled emitters from swapping apparent ages between ticks.
- `FireRenderer.sync(active:)` sets each pooled entity's position and uniform scale from its sample.
- At natural burnout, the existing tick removes the active visual and emits one char event. A fire extinguished at any growth stage disappears immediately and never emits char.

## Empty-window lifecycle

- Add a stable main-window scene ID and apply it to the existing `WindowGroup`.
- After `openImmersiveSpace` returns `.opened`, dismiss that main window. Do not dismiss it on cancellation or error.
- `ImmersiveMeshView` reopens the main window when the immersive scene disappears, including Digital Crown exit.
- End Training dismisses the immersive scene through its existing state flow; reopening creates the normal phase-selection surface rather than an empty volume.
- Do not add or remove another window scene, and do not change the existing volumetric style used by Phase 1.

## UI decision brief

- Surface type: Live spatial training HUD and physical rescue interaction.
- Platform idiom: Branded native visionOS using SwiftUI, RealityKit, ARKit, native materials, and gaze-and-pinch targeting.
- Product thesis: Keep hazards and rescue targets legible while keeping status out of the learner's central field of view.
- Density: Sparse and safety-oriented.
- Hierarchy: Physical hazards and Gabe are primary; health/challenges stay upper-left; timer stays upper-right; extinguisher stays lower-right; carried Gabe stays lower-left.
- Materials: Existing visionOS glass for status surfaces; no new decorative UI panel for carried Gabe.
- Motion budget: Functional. Head stabilization and fire growth communicate state; rescue relocation is immediate rather than decorative.
- Reduced-motion behavior: Preserve head stabilization and state changes; add no decorative rescue or fire animation beyond required continuous growth.
- Bans: No inventory window, floating casualty fallback, powder particles, centre-blocking status UI, temporary exit, or generic anchor framework.

## Error and lifecycle behavior

- Casualty asset-load failure preserves the active scenario and reports a concise error.
- No suitable seven-metre scanned floor keeps the casualty pending and prompts the learner to scan farther.
- A casualty pinch after rescue is ignored.
- An extinguisher or casualty pinch always returns early from scene fire-start routing.
- Reset cancels both delayed tasks, removes active entities, resets the single rescue objective, then waits for the next successful fire and extinguisher sequence.
- Loss of tracked head pose temporarily freezes carried presentation at its last valid transform and stops extinguisher spray through the existing safety path.

## Validation

No automated scenario tests will be added, following the approved project constraint.

Local validation:

- Strict Debug visionOS Simulator build.
- Strict Release visionOS Simulator build.
- Strict generic visionOS device build with code signing disabled.
- Xcode static analysis.
- `Info.plist`, bundle resources, exact constants/call sites, and `git diff --check`.

Physical Vision Pro acceptance:

- Extinguisher coarse gaze targeting succeeds across roughly twice the former target bounds.
- Pickup pinch still cannot spray; a later held pinch does.
- The brighter cone remains visible and originates at the black hose nozzle through head movement.
- Gabe appears approximately five seconds after the extinguisher actually appears and approximately seven metres away on scanned floor.
- One gaze-and-pinch rescue removes world Gabe immediately and shows a 20%-scale lower-left carried Gabe.
- Gabe cannot be rescued twice and reset creates a clean new attempt.
- Each fire grows smoothly from 1x to approximately 4x before natural char.
- Extinguished fires disappear at their current size without char.
- The empty volumetric main window is absent during immersion and the normal main window returns after Digital Crown exit.

Simulator and compiler validation cannot establish gaze hit quality, nozzle visual alignment, real scanned-floor placement, perceived five-second timing, carried-view comfort, or window behavior on hardware. Those remain physical Vision Pro gates.
