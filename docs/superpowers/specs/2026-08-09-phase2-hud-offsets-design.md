# Phase 2 HUD Offset Adjustment Design

## Goal

Move the Phase 2 timer to the top-middle and slightly lower, while moving the health and message stack lower on the left without changing its content or motion behavior.

## Placement contract

All positions remain head-relative at the existing depth of `-1.15` metres.

- Timer: change from `(x: 0.45, y: 0.25, z: -1.15)` to `(x: 0, y: 0.225, z: -1.15)`. This centres it horizontally and lowers its current vertical offset by 10%.
- Health/message stack: change from `(x: -0.45, y: 0.25, z: -1.15)` to `(x: -0.45, y: 0.20, z: -1.15)`. This preserves left alignment and lowers its current vertical offset by 20%.
- Result screen: retain `(x: 0, y: 0, z: -0.95)`.

## Preserved behavior

- Keep the existing approximately 60 Hz presentation loop and `HeadFollowSmoother` behavior.
- Keep the timer, health, casualty guidance, and extinguisher guidance content unchanged.
- Keep the attachments separate and peripheral; do not introduce a shared HUD canvas.
- Keep visibility transitions and result-screen behavior unchanged.

## Verification

- Run a strict Debug visionOS Simulator build with Swift warnings treated as errors.
- Run `git diff --check` and confirm only the two HUD translation values changed in implementation.
- Physical Apple Vision Pro validation remains required to judge final comfort and field-of-view placement.
