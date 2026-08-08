import SwiftUI
import RealityKit

// MARK: - Room Loader

/// Loads new_apple_room.usdz from the app bundle, sets up collision/input so gestures
/// and tap-to-place work on it, and names the root "tabletopGroup" so the rest of the
/// scene code can find it via `content.entities.first(where:)`.
@MainActor
func loadRoomEntity() async -> Entity {
    let group = Entity()
    group.name = "tabletopGroup"

    let room: Entity?
    do {
        room = try await Entity(named: "new_apple_room", in: .main)
        print("✅ Loaded new_apple_room via Entity(named:in: .main)")
    } catch {
        print("⚠️ Entity(named:in: .main) failed: \(error). Trying contentsOf URL…")
        if let url = Bundle.main.url(forResource: "new_apple_room", withExtension: "usdz") {
            print("   Bundle URL: \(url.path)")
            do {
                room = try await Entity(contentsOf: url)
                print("✅ Loaded new_apple_room via contentsOf URL")
            } catch {
                print("❌ contentsOf URL also failed: \(error)")
                room = nil
            }
        } else {
            print("❌ Bundle.main.url(forResource: \"new_apple_room\", withExtension: \"usdz\") returned nil")
            room = nil
        }
    }

    guard let room else { return group }

    room.name = "roomModel"

    // Fit the model into a ~0.4 m footprint centered at group origin, floor at y=0.
    let bounds = room.visualBounds(relativeTo: nil)
    let size = bounds.max - bounds.min
    let maxHorizontal = max(size.x, size.z)
    let targetSize: Float = 0.4
    let scale = maxHorizontal > 0 ? targetSize / maxHorizontal : 1.0
    room.scale = SIMD3(repeating: scale)

    let center = (bounds.min + bounds.max) * 0.5
    room.position = SIMD3(
        -center.x * scale,
        -bounds.min.y * scale,
        -center.z * scale
    )
    print("📐 Applied scale \(scale), position \(room.position)")

    group.addChild(room)
    room.generateCollisionShapes(recursive: true)
    enableInputTargeting(room)

    // Wrap-around collider on the group itself so drag/magnify/rotate gestures
    // reliably target the tabletop even if the USDZ hierarchy has entities without
    // meshes. Sized to encompass the whole scaled room + a small margin.
    let scaledSize = size * scale
    let boxSize = SIMD3<Float>(
        max(scaledSize.x, 0.1) + 0.05,
        max(scaledSize.y, 0.1) + 0.05,
        max(scaledSize.z, 0.1) + 0.05
    )
    group.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: boxSize)]))
    group.components.set(InputTargetComponent())
    group.components.set(HoverEffectComponent())

    return group
}

private func enableInputTargeting(_ entity: Entity) {
    entity.components.set(InputTargetComponent())
    for child in entity.children {
        enableInputTargeting(child)
    }
}

private func isDescendant(of ancestorName: String, entity: Entity) -> Bool {
    var current: Entity? = entity.parent
    while let e = current {
        if e.name == ancestorName { return true }
        current = e.parent
    }
    return false
}

// MARK: - Floor Grid

/// Casts a downward ray at each cell center to determine walkability. Must run AFTER
/// the tabletop has been added to the RealityView content (so `.scene` is non-nil).
@MainActor
func computeFloorGrid(tabletop: Entity, roomBoundsLocal: BoundingBox) -> FloorGrid {
    let cellSize: Float = 0.025
    let width = roomBoundsLocal.max.x - roomBoundsLocal.min.x
    let depth = roomBoundsLocal.max.z - roomBoundsLocal.min.z
    let cols = max(1, Int(width / cellSize))
    let rows = max(1, Int(depth / cellSize))
    let origin = SIMD3<Float>(roomBoundsLocal.min.x, 0.0, roomBoundsLocal.min.z)
    let fire = Array(repeating: Array(repeating: 0, count: cols), count: rows)

    guard let scene = tabletop.scene else {
        print("⚠️ computeFloorGrid: tabletop not yet in scene")
        return FloorGrid(cols: cols, rows: rows, cellSize: cellSize,
                         originLocal: origin, floorY: 0.0,
                         walkable: Array(repeating: Array(repeating: false, count: cols), count: rows),
                         fireIntensity: fire)
    }

    // Pass 1: cast a ray at each cell center, record the topmost hit's Y.
    let rayHeight: Float = 0.5
    let rayEndY:   Float = -0.2
    var topmostY = Array(repeating: Array(repeating: -Float.infinity, count: cols), count: rows)

    for row in 0..<rows {
        for col in 0..<cols {
            let localCenter = SIMD3<Float>(
                origin.x + (Float(col) + 0.5) * cellSize,
                rayHeight,
                origin.z + (Float(row) + 0.5) * cellSize
            )
            let originWorld = tabletop.convert(position: localCenter, to: nil)
            let endWorld    = tabletop.convert(
                position: SIMD3<Float>(localCenter.x, rayEndY, localCenter.z),
                to: nil
            )
            let hits = scene.raycast(from: originWorld, to: endWorld)
            if let maxY = hits.map({ tabletop.convert(position: $0.position, from: nil).y }).max() {
                topmostY[row][col] = maxY
            }
        }
    }

    // Auto-detect floor Y: the lowest "topmost hit" across all cells that had a hit is
    // the bare floor. Cells with walls/furniture on top will have larger topmost Y values.
    let allHits = topmostY.flatMap { $0 }.filter { $0.isFinite }
    let floorY = allHits.min() ?? 0.0

    // Pass 2: walkable if topmost hit is close to detected floor Y (no obstacle on top).
    let floorTolerance: Float = 0.015
    var walkable = Array(repeating: Array(repeating: false, count: cols), count: rows)
    for row in 0..<rows {
        for col in 0..<cols {
            let y = topmostY[row][col]
            walkable[row][col] = y.isFinite && abs(y - floorY) < floorTolerance
        }
    }

    let grid = FloorGrid(cols: cols, rows: rows, cellSize: cellSize,
                         originLocal: origin, floorY: floorY,
                         walkable: walkable, fireIntensity: fire)
    print("🟩 Floor grid: \(grid.walkableCount)/\(cols * rows) walkable, detected floorY=\(floorY)")
    return grid
}

func buildGridOverlay(_ grid: FloorGrid) -> Entity {
    let overlay = Entity()
    overlay.name = "gridOverlay"
    let liftY: Float = 0.003
    let lineT: Float = 0.0008
    let totalW = Float(grid.cols) * grid.cellSize
    let totalD = Float(grid.rows) * grid.cellSize

    let lineMat = UnlitMaterial(color: UIColor.white.withAlphaComponent(0.15))
    for i in 0...grid.cols {
        let x = grid.originLocal.x + Float(i) * grid.cellSize
        let mesh = MeshResource.generateBox(width: lineT, height: 0.0005, depth: totalD)
        let e = ModelEntity(mesh: mesh, materials: [lineMat])
        e.position = [x, liftY, grid.originLocal.z + totalD / 2]
        overlay.addChild(e)
    }
    for j in 0...grid.rows {
        let z = grid.originLocal.z + Float(j) * grid.cellSize
        let mesh = MeshResource.generateBox(width: totalW, height: 0.0005, depth: lineT)
        let e = ModelEntity(mesh: mesh, materials: [lineMat])
        e.position = [grid.originLocal.x + totalW / 2, liftY, z]
        overlay.addChild(e)
    }

    let blockedMat = UnlitMaterial(color: UIColor.red.withAlphaComponent(0.12))
    for row in 0..<grid.rows {
        for col in 0..<grid.cols {
            guard !grid.walkable[row][col] else { continue }
            let mesh = MeshResource.generateBox(
                width: grid.cellSize * 0.9,
                height: 0.0005,
                depth: grid.cellSize * 0.9
            )
            let e = ModelEntity(mesh: mesh, materials: [blockedMat])
            e.position = grid.cellCenterLocal(col: col, row: row) + [0, liftY, 0]
            overlay.addChild(e)
        }
    }
    return overlay
}

// MARK: - Placed Item Helpers

func colorForCategory(_ category: ItemCategory) -> UIColor {
    switch category {
    case .furniture:  return UIColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)
    case .appliances: return UIColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0)
    case .belongings: return UIColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 1.0)
    }
}

func buildPlacedItemEntity(_ item: PlacedItem) -> ModelEntity {
    let isCone = (item.itemType.name == "Bed")
    let mesh: MeshResource
    let collisionShape: ShapeResource
    let yLift: Float
    let matColor: UIColor

    if isCone {
        let coneHeight: Float = 0.08          // 8 cm — clearly visible
        let coneRadius: Float = 0.03          // 3 cm base
        mesh = MeshResource.generateCone(height: coneHeight, radius: coneRadius)
        // Generous box collider — easier to click in the sim
        collisionShape = .generateBox(size: SIMD3<Float>(coneRadius * 2.5, coneHeight * 1.2, coneRadius * 2.5))
        yLift = coneHeight / 2
        matColor = UIColor.systemOrange       // saturated color for visibility
    } else {
        mesh = MeshResource.generateBox(size: 0.028, cornerRadius: 0.004)
        collisionShape = .generateBox(size: SIMD3<Float>(repeating: 0.028))
        yLift = 0.017
        matColor = colorForCategory(item.itemType.category)
    }

    var mat = SimpleMaterial()
    mat.color = .init(tint: matColor)
    mat.roughness = .float(0.6)
    let entity = ModelEntity(mesh: mesh, materials: [mat])
    entity.name = "placed_\(item.id.uuidString)"
    // item.position.y comes from grid.cellCenterLocal which is the detected floor Y;
    // add yLift so the item sits ON the floor rather than embedded in it.
    entity.position = SIMD3(item.position.x, item.position.y + yLift, item.position.z)
    entity.collision = CollisionComponent(shapes: [collisionShape])
    entity.components.set(InputTargetComponent())
    entity.components.set(HoverEffectComponent())
    entity.components.set(PlacedItemComponent(itemID: item.id))
    return entity
}

// MARK: - Scene View

struct SceneView: View {
    let layoutID: Int
    @Binding var screen: AppScreen
    @Environment(SceneViewModel.self) var viewModel

    @State private var scaleDelta: Float = 1.0
    @State private var rotationDelta: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var draggingItemID: UUID? = nil
    @State private var itemDragDelta: SIMD3<Float> = .zero

    // Initial tilt: ~20° toward the user so the floor plan is visible straight-on.
    // Rotating around Y then composes on top of this, revealing the 3D structure.
    private let baseTilt = simd_quatf(angle: -.pi / 9, axis: [1, 0, 0])

    var layout: LayoutConfig { LayoutConfig.all.first { $0.id == layoutID }! }

    var body: some View {
        RealityView { content, attachments in
            let tabletop = await loadRoomEntity()
            tabletop.position = viewModel.tabletopTranslation
            tabletop.orientation = baseTilt
            content.add(tabletop)
            viewModel.tabletopAnchor = tabletop

            // Compute walkability grid from the loaded room (invisible — used only for snap
            // logic in handleTap and item drag). Must run AFTER content.add(tabletop).
            if let room = tabletop.findEntity(named: "roomModel") {
                let boundsLocal = room.visualBounds(relativeTo: tabletop)
                viewModel.floorGrid = computeFloorGrid(tabletop: tabletop, roomBoundsLocal: boundsLocal)
            }

            // Billboarded palette to the right of the tabletop.
            if let palette = attachments.entity(for: "palette") {
                palette.name = "paletteAttachment"
                palette.position = [0.25, 0.02, 0.05]
                palette.components.set(BillboardComponent())
                content.add(palette)
            }

            // Billboarded nav bar hovering above the tabletop.
            if let navbar = attachments.entity(for: "navbar") {
                navbar.name = "navbarAttachment"
                navbar.position = [-0.1, 0.15, 0.05]
                navbar.components.set(BillboardComponent())
                content.add(navbar)
            }
        } update: { content, _ in
            guard let tabletop = content.entities.first(where: { $0.name == "tabletopGroup" }) else { return }
            tabletop.position = viewModel.tabletopTranslation
            tabletop.scale    = SIMD3(repeating: viewModel.tabletopScale * scaleDelta)
            // Compose: baseTilt (fixed initial pose) → committed user rotation → in-progress gesture delta
            tabletop.orientation = rotationDelta * viewModel.tabletopRotation * baseTilt

            // Live drag preview for placed items — keep current Y (already correct
            // relative to floor); only shift XZ by the accumulated drag delta.
            if let itemID = draggingItemID,
               let idx = viewModel.placedItems.firstIndex(where: { $0.id == itemID }),
               let entity = tabletop.findEntity(named: "placed_\(itemID.uuidString)") {
                let base = viewModel.placedItems[idx].position
                entity.position = SIMD3(base.x + itemDragDelta.x, entity.position.y, base.z + itemDragDelta.z)
            }
        } attachments: {
            Attachment(id: "palette") {
                ItemPaletteView()
                    .environment(viewModel)
            }
            Attachment(id: "navbar") {
                HStack(spacing: 14) {
                    Button {
                        resetViewModel()
                        screen = .layoutSelection
                    } label: {
                        Label("Layouts", systemImage: "chevron.left")
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Divider().frame(height: 18)
                    Text(layout.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassBackgroundEffect()
            }
        }
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(rotateGesture)
        .simultaneousGesture(rotationDragGesture)
        .simultaneousGesture(tapGesture)
        .simultaneousGesture(itemDragGesture)
        .onChange(of: viewModel.selectedItemType) { _, newValue in
            // Click-drag-drop UX: tapping a palette item auto-spawns it at the room
            // center already selected, so the user can immediately pinch and drag.
            guard let itemType = newValue else { return }
            print("🎯 Palette selection changed → \(itemType.name)")
            guard itemType.name == "Bed" else {
                print("   (not a cone — falling back to tap-to-place)")
                return
            }
            guard let tabletop = viewModel.tabletopAnchor else {
                print("❌ No tabletopAnchor — room hasn't loaded yet")
                return
            }
            let spawnLocal = snapToGrid(SIMD3<Float>(0, 0, 0))
            let placed = viewModel.placeItem(itemType, at: spawnLocal)
            let entity = buildPlacedItemEntity(placed)
            tabletop.addChild(entity)
            viewModel.selectedPlacedItemID = placed.id
            print("🔶 Spawned cone at tabletop-local \(entity.position), name=\(entity.name)")
        }
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                scaleDelta = Float(value.magnification)
            }
            .onEnded { value in
                viewModel.tabletopScale *= Float(value.magnification)
                viewModel.tabletopScale = max(0.3, min(3.0, viewModel.tabletopScale))
                scaleDelta = 1.0
            }
    }

    /// Two-hand twist gesture. Free-axis (no constraint), so the room can yaw, pitch,
    /// and roll on real AVP hardware. Diagnostic log confirms it fires and shows the
    /// magnitude — useful when validating flipping behavior.
    private var rotateGesture: some Gesture {
        RotateGesture3D()   // NO axis constraint — free 3D rotation
            .targetedToAnyEntity()
            .onChanged { value in
                rotationDelta = quatFromRotation3D(value.rotation)
            }
            .onEnded { value in
                let delta = quatFromRotation3D(value.rotation)
                let axis = value.rotation.axis
                let angleDeg = value.rotation.angle.degrees
                print("🔄 RotateGesture3D ended — angle=\(angleDeg)°, axis=(\(axis.x),\(axis.y),\(axis.z))")
                viewModel.tabletopRotation = simd_normalize(delta * viewModel.tabletopRotation)
                rotationDelta = simd_quatf(angle: 0, axis: [0, 1, 0])
            }
    }

    /// Extract a `simd_quatf` from a Spatial `Rotation3D` unambiguously via imag/real
    /// rather than relying on `.vector` component order.
    private func quatFromRotation3D(_ rot: Rotation3D) -> simd_quatf {
        let q = rot.quaternion
        return simd_quatf(
            ix: Float(q.imag.x),
            iy: Float(q.imag.y),
            iz: Float(q.imag.z),
            r:  Float(q.real)
        )
    }

    /// One-hand drag rotation for sim testing AND single-hand AVP use. Reads horizontal
    /// screen drag as yaw (around Y) and vertical drag as pitch (around X). Long enough
    /// vertical drag flips the room upside-down. Only fires on drags that DON'T start
    /// on a placed item (so `itemDragGesture` still handles those).
    private var rotationDragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard value.entity.components[PlacedItemComponent.self] == nil else { return }
                let radPerPt: Float = 0.007   // ~0.4° per screen point
                let dx = Float(value.translation.width)  * radPerPt
                let dy = Float(value.translation.height) * radPerPt
                let yaw   = simd_quatf(angle: dx, axis: SIMD3<Float>(0, 1, 0))
                let pitch = simd_quatf(angle: dy, axis: SIMD3<Float>(1, 0, 0))
                rotationDelta = yaw * pitch
            }
            .onEnded { value in
                guard value.entity.components[PlacedItemComponent.self] == nil else { return }
                let radPerPt: Float = 0.007
                let dx = Float(value.translation.width)  * radPerPt
                let dy = Float(value.translation.height) * radPerPt
                let yaw   = simd_quatf(angle: dx, axis: SIMD3<Float>(0, 1, 0))
                let pitch = simd_quatf(angle: dy, axis: SIMD3<Float>(1, 0, 0))
                let delta = yaw * pitch
                viewModel.tabletopRotation = simd_normalize(delta * viewModel.tabletopRotation)
                rotationDelta = simd_quatf(angle: 0, axis: [0, 1, 0])
                let yawDeg = dx * 180 / .pi
                let pitchDeg = dy * 180 / .pi
                print("🎡 DragRotate ended — yaw=\(yawDeg)°, pitch=\(pitchDeg)°")
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                handleTap(value: value)
            }
    }

    /// Drag a placed item (e.g., a cone) to a new floor cell. Snaps to grid on release
    /// and rejects the move if the destination cell is blocked (reverts to origin).
    private var itemDragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let component = value.entity.components[PlacedItemComponent.self],
                      let tabletop = viewModel.tabletopAnchor else {
                    if draggingItemID == nil {
                        // Log which entity was hit for debugging why drag didn't engage
                        print("↔️ Drag hit entity '\(value.entity.name)' — no PlacedItemComponent, ignoring")
                    }
                    return
                }
                if draggingItemID == nil {
                    draggingItemID = component.itemID
                    viewModel.selectedItemType = nil
                    viewModel.selectedPlacedItemID = component.itemID
                    print("✋ Started dragging placed item \(component.itemID.uuidString.prefix(6))")
                }
                let t = value.translation3D
                let worldDelta = SIMD3<Float>(Float(t.x), Float(t.y), Float(t.z))
                let origin = tabletop.convert(position: .zero, from: nil)
                let tip = tabletop.convert(position: worldDelta, from: nil)
                itemDragDelta = SIMD3(tip.x - origin.x, 0, tip.z - origin.z)
            }
            .onEnded { value in
                defer {
                    draggingItemID = nil
                    itemDragDelta = .zero
                }
                guard let itemID = draggingItemID,
                      let idx = viewModel.placedItems.firstIndex(where: { $0.id == itemID }),
                      let tabletop = viewModel.tabletopAnchor,
                      let entity = tabletop.findEntity(named: "placed_\(itemID.uuidString)") else { return }

                let t = value.translation3D
                let worldDelta = SIMD3<Float>(Float(t.x), Float(t.y), Float(t.z))
                let origin = tabletop.convert(position: .zero, from: nil)
                let tip = tabletop.convert(position: worldDelta, from: nil)
                let localDelta = SIMD3<Float>(tip.x - origin.x, 0, tip.z - origin.z)

                let candidate = SIMD3<Float>(
                    viewModel.placedItems[idx].position.x + localDelta.x,
                    viewModel.placedItems[idx].position.y,
                    viewModel.placedItems[idx].position.z + localDelta.z
                )

                let snapped = snapToGrid(candidate)
                // Preserve the item's Y-lift offset above the floor while snapping XZ.
                let originalLift = entity.position.y - viewModel.placedItems[idx].position.y
                viewModel.placedItems[idx].position.x = snapped.x
                viewModel.placedItems[idx].position.y = snapped.y
                viewModel.placedItems[idx].position.z = snapped.z
                entity.position = SIMD3(snapped.x, snapped.y + originalLift, snapped.z)
            }
    }

    // MARK: - Tap Handling

    @MainActor
    private func handleTap(value: EntityTargetValue<SpatialTapGesture.Value>) {
        let tappedEntity = value.entity

        if let component = tappedEntity.components[PlacedItemComponent.self] {
            let tappedID = component.itemID
            if viewModel.selectedPlacedItemID == tappedID {
                viewModel.selectedPlacedItemID = nil
            } else {
                viewModel.selectedItemType = nil
                viewModel.selectedPlacedItemID = tappedID
            }
            return
        }

        // Tap-to-place is retained for the box items; the cone flow uses auto-spawn +
        // drag (see .onChange handler on selectedItemType in body). Tap here still
        // handles floor taps for non-cone items.
        guard let itemType = viewModel.selectedItemType,
              itemType.name != "Bed",  // cone uses auto-spawn flow
              let tabletop = viewModel.tabletopAnchor,
              tappedEntity.name != "paletteAttachment",
              !isDescendant(of: "paletteAttachment", entity: tappedEntity) else { return }

        let worldLocation = value.convert(value.location3D, from: .local, to: .scene)
        let localLocation = tabletop.convert(position: worldLocation, from: nil)
        let snappedLocal = snapToGrid(localLocation)

        let placed = viewModel.placeItem(itemType, at: snappedLocal)
        let placedEntity = buildPlacedItemEntity(placed)
        tabletop.addChild(placedEntity)
    }

    /// Snap a tabletop-local position to the nearest WALKABLE grid cell center.
    /// If the tapped cell is blocked (wall/furniture), spirals outward to the nearest
    /// open cell. Falls back to raw position if the grid isn't ready.
    private func snapToGrid(_ local: SIMD3<Float>) -> SIMD3<Float> {
        guard let grid = viewModel.floorGrid else {
            return SIMD3(local.x, 0, local.z)
        }
        return grid.nearestWalkableCenter(to: local) ?? SIMD3(local.x, grid.floorY, local.z)
    }

    private func resetViewModel() {
        viewModel.tabletopAnchor = nil
        viewModel.floorGrid = nil
        viewModel.selectedItemType = nil
        viewModel.selectedPlacedItemID = nil
        viewModel.placedItems = []
        viewModel.tabletopTranslation = [-0.1, -0.1, 0.05]
        viewModel.tabletopScale = 1.0
        viewModel.tabletopRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }
}
