# Phase 2 HUD Offset Adjustment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Phase 2 timer to the slightly lowered top-middle position and lower the left health/message stack without changing HUD smoothing, depth, content, or result placement.

**Architecture:** Retain the existing separate RealityView attachments and head-relative transform pipeline. Change only the `x` and `y` translation constants passed to the two HUD attachment transforms in `ImmersiveMeshView.updatePresentationTransforms`.

**Tech Stack:** Swift 6, SwiftUI, RealityKit, visionOS 27 SDK, Xcode 27 beta.

## Global Constraints

- Work on the existing `fire-simulator` branch.
- Timer transform must be `(x: 0, y: 0.225, z: -1.15)`.
- Health/message transform must be `(x: -0.45, y: 0.20, z: -1.15)`.
- Result transform remains `(x: 0, y: 0, z: -0.95)`.
- Do not change `HeadFollowSmoother`, presentation frequency, HUD content, visibility, or styling.
- Do not add automated scenario tests; use strict compilation and an exact source diff.

---

### Task 1: Apply and verify the two HUD offsets

**Files:**

- Modify: `respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift`

**Interfaces:**

- Consumes: `updatePresentationTransforms(headTransform:statusEntity:timerEntity:resultEntity:)`.
- Produces: updated head-relative transforms for the existing status and timer attachments.

- [ ] **Step 1: Change the status and timer translations**

Replace only the two attachment transforms with:

```swift
statusEntity?.transform = Transform(
    matrix: headTransform * translation(x: -0.45, y: 0.20, z: -1.15)
)
timerEntity?.transform = Transform(
    matrix: headTransform * translation(x: 0, y: 0.225, z: -1.15)
)
```

- [ ] **Step 2: Confirm the exact implementation diff**

Run:

```bash
git diff --check
git diff -- 'respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift'
```

Expected: only the status `y` value and timer `x`/`y` values change; status `x`/`z`, timer `z`, and result transform remain unchanged.

- [ ] **Step 3: Run a strict Debug simulator build**

```bash
DEVELOPER_DIR=/Users/kc/Downloads/Xcode-beta.app/Contents/Developer xcodebuild -quiet -project respondR.xcodeproj -scheme respondR -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/respondR-hud-offsets CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Expected: exit code 0.

- [ ] **Step 4: Commit the placement change**

```bash
git add 'respondR/Resources/simulation (phase 2)/simulation/ImmersiveMeshView.swift'
git commit -m 'fix: adjust phase 2 hud positions'
```

- [ ] **Step 5: Record the remaining device gate**

Report that perceived placement and comfort still require a physical Apple Vision Pro check.
