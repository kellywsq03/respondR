# Phase 2 Fire Extinguisher Design

## Scope

Add one usable fire extinguisher to Phase 2 fire mode. The feature uses the supplied `respondR/Resources/Fire_Extinguisher.usdz`, avoids powder particles, provides continuous spray feedback, and distinguishes manual extinguishing from natural fire burnout.

No inventory screen, equipment menu, consumable-ammunition system, hand-joint tracking, or additional Phase 2 scenario content is included.

## Player flow

1. Entering the Phase 2 immersive space in fire mode starts a five-second spawn delay.
2. After the delay, the extinguisher appears 0.9 metres forward, 0.25 metres right, and 0.4 metres below the user's current device anchor. It remains fixed at that world position until picked up.
3. The player taps the extinguisher once to pick it up. Pickup permanently equips it for the current Phase 2 session; there is no inventory state or inventory UI.
4. The equipped extinguisher remains visible at its true physical scale in a natural lower-right, head-relative held position.
5. The player looks toward a fire and pinches and holds the equipped extinguisher to spray.
6. The white spray cone and hiss exist only while that pinch remains active. Releasing or cancelling the pinch stops both immediately.

Resetting Phase 2 ends any active spray, removes the equipped or spawned extinguisher, clears its state, and begins a fresh five-second spawn cycle. Leaving the immersive space cancels the delayed spawn and removes all extinguisher effects and state.

## Asset sizing and interaction

The supplied USDZ resolves to approximately two metres tall because it declares centimetre units and also contains a 100-times root scale. After loading, measure the entity's visual bounds and uniformly scale it to a target height of 0.55 metres. Bounds-based normalization keeps the extinguisher true-to-size even if its internal authored scale changes later.

The pickup entity receives collision, input-target, and hover components recursively so gaze-and-pinch targeting works on the visible model. The implementation must not replace the supplied asset with procedural placeholder geometry during normal gameplay. An asset-loading failure is surfaced through the existing Phase 2 status/error state and leaves the feature unavailable rather than displaying a misleading substitute.

## Spray feedback and aiming

The spray indicator is a lightweight translucent white cone with a two-metre reach and a 17.5-degree half-angle. Its apex begins at the extinguisher nozzle and its direction follows the user's current device-forward aiming direction.

The cone is disabled by default. It becomes visible on pinch start, remains visible only while the pinch is held, and is disabled immediately on release, gesture cancellation, reset, or immersive-space exit. It is never shown as a passive aiming guide, pickup hint, or lingering effect. No powder, smoke, cloud, or particle emitter is used for extinguisher spray.

## Audio

While spraying, a looping filtered-noise hiss plays spatially from the extinguisher. RealityKit's real-time audio generator supplies the sound without adding a large audio asset. Pinch start begins playback and pinch release or cancellation stops it. Audio failure must not prevent the cone or extinguishing behavior from working.

## Fire interaction and lifecycle

Spray geometry is represented independently from RealityKit rendering by an apex, normalized direction, maximum distance, and half-angle. On each existing simulation tick while spraying, the fire simulation removes every active igniting or burning cell whose centre falls inside that cone.

Manual extinguishing follows a separate lifecycle path from natural burnout:

- An extinguished cell is removed from the active runtime set immediately.
- It can no longer spread fire.
- It is absent from the positions used by the proximity-damage calculation, so it stops damaging the player on the same simulation update.
- It is not added to the naturally burnt-out set or newly-burnt queue.
- It therefore creates no black char mark.

A cell that reaches the existing natural burn-duration limit continues through the current burnt-out path and produces its existing mesh-conforming black char. The extinguisher must not remove previously created natural-burn char marks.

## Player guidance

Show concise, state-specific guidance in the existing head-following Phase 2 HUD:

- Before pickup: **"Tap the extinguisher to pick it up."**
- After pickup: **"Pinch and hold the extinguisher to spray. Aim the white cone at the fire."**

No additional tutorial, inventory panel, or modal is added.

## Component boundaries

- `FireSimulation` owns manual removal of active cells and guarantees that extinguished cells never enter the natural-burn char queue.
- A pure spray-geometry value owns cone containment calculations and has no RealityKit dependency.
- An extinguisher controller owns delayed spawning, USDZ loading and size normalization, pickup/equipped state, head-relative placement, cone visibility, and hiss playback.
- `ImmersiveMeshView` connects input gestures and the existing 100-millisecond simulation tick to the extinguisher controller and `FireSimulation`.
- `AppModel` exposes only the small amount of observable equipment state needed for the concise guidance text.

## Failure and cleanup behavior

- Cancelling the five-second task prevents a late spawn after reset or exit.
- Spray cannot start before pickup.
- Losing or cancelling the active gesture always hides the cone and stops audio.
- Missing device tracking for a tick stops extinguishing for that tick rather than reusing stale aim data.
- Reset and exit are idempotent and remove spawned entities, audio controllers, tasks, and spray state.
- Asset or audio errors are logged and surfaced without crashing the immersive session.

## Test and acceptance plan

Test-first core checks will prove:

- bounds-to-target-height scaling produces 0.55 metres and preserves aspect ratio;
- points inside, outside, behind, and beyond the spray cone are classified correctly;
- only active cells inside the cone are extinguished;
- extinguished cells disappear from active positions and never enter the char queue;
- naturally expired cells still enter the char queue;
- reset clears equipment and spray state and restarts the spawn lifecycle;
- the cone and hiss state exist only for the duration of an active held pinch.

Fresh validation will include the core checks, Swift parsing where useful, `git diff --check`, simulator and generic-device builds, and Xcode analysis using the installed full Xcode. Simulator and device builds do not establish live hand comfort, world placement, spatial audio quality, or aim accuracy; those remain physical Apple Vision Pro acceptance checks.
