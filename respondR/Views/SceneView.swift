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

    // Diagnostic: dump the loaded entity hierarchy so we can verify names match RCP.
    print("🌳 Loaded room entity hierarchy:")
    dumpHierarchy(room)

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

@MainActor
func loadAssetEntity(named assetName: String) async -> Entity {
    let group = Entity()
    group.name = "tabletopGroup"

    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let itemsURL = documentsURL.appendingPathComponent("items")
    let assetURL = itemsURL.appendingPathComponent(assetName)

    let room: Entity?
    do {
        room = try await Entity(contentsOf: assetURL)
        print("✅ Loaded asset via contentsOf URL: \(assetURL.path)")
    } catch {
        print("❌ Failed loading asset at \(assetURL.path): \(error)")
        room = nil
    }

    guard let room else { return group }

    room.name = "roomModel"

    // Fit the model into a ~0.6 m footprint centered at group origin, floor at y=0.
    let bounds = room.visualBounds(relativeTo: nil)
    let size = bounds.max - bounds.min
    let maxHorizontal = max(size.x, size.z)
    let targetSize: Float = 0.6
    let scale = maxHorizontal > 0 ? targetSize / maxHorizontal : 1.0
    room.scale = SIMD3(repeating: scale)

    let center = (bounds.min + bounds.max) * 0.5
    room.position = SIMD3(
        -center.x * scale,
        -bounds.min.y * scale,
        -center.z * scale
    )
    print("📐 Applied scale \(scale), position \(room.position) for asset")

    group.addChild(room)
    room.generateCollisionShapes(recursive: true)
    enableInputTargeting(room)

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
    var current: Entity? = entity
    while let e = current {
        if e.name == ancestorName { return true }
        current = e.parent
    }
    return false
}

private func fmt(_ v: SIMD3<Float>) -> String {
    String(format: "(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
}

extension Entity {
    /// Depth-first walk yielding every ModelEntity in the subtree (self included).
    /// Used by `computeFloorGrid` to convert obstacle group hierarchies into
    /// per-mesh bounding boxes without needing a scene raycast.
    func descendantModelEntities() -> [ModelEntity] {
        var out: [ModelEntity] = []
        if let me = self as? ModelEntity, me.model != nil { out.append(me) }
        for child in children { out.append(contentsOf: child.descendantModelEntities()) }
        return out
    }
}

/// Prints an ASCII map of walkability around a target cell (radius cells in each direction).
/// `*` = tapped cell, `.` = walkable, `#` = blocked, `o` = occupied.
@MainActor
private func dumpNeighborhood(grid: FloorGrid, col: Int, row: Int, radius: Int) {
    print("   Neighborhood (radius \(radius)) — * tapped, . walkable, # blocked, o occupied:")
    for r in (row - radius)...(row + radius) {
        var line = "     "
        for c in (col - radius)...(col + radius) {
            if c < 0 || c >= grid.cols || r < 0 || r >= grid.rows {
                line += " "
            } else if c == col && r == row {
                line += "*"
            } else if grid.occupiedBy[r][c] != nil {
                line += "o"
            } else if grid.walkable[r][c] {
                line += "."
            } else {
                line += "#"
            }
        }
        print(line)
    }
}

/// Prints the entity subtree names & types for diagnosing why walkability check fails.
private func dumpHierarchy(_ entity: Entity, depth: Int = 0) {
    let indent = String(repeating: "  ", count: depth)
    let hasMesh = (entity as? ModelEntity)?.model != nil
    print("\(indent)- \(entity.name.isEmpty ? "<unnamed>" : entity.name) \(hasMesh ? "[mesh]" : "")")
    for child in entity.children {
        dumpHierarchy(child, depth: depth + 1)
    }
}

// MARK: - Floor Grid

/// Casts a downward ray at each cell center to determine walkability. Must run AFTER
/// the tabletop has been added to the RealityView content (so `.scene` is non-nil).
/// Builds the floor grid using semantic entity names from the USDZ.
/// - `Floor_grp` defines the walkable floor bounds and floor Y level.
/// - `Arch_grp` (walls, doors) and `Object_grp` (furniture) are treated as blocked.
/// - A cell is walkable ONLY if a downward raycast hits nothing from Arch_grp or Object_grp.
@MainActor
func computeFloorGrid(tabletop: Entity) -> FloorGrid {
    let cellSize: Float = 0.015

    guard let floorGrp = tabletop.findEntity(named: "Floor_grp") else {
        print("⚠️ Floor_grp not found in USDZ — cannot build grid")
        return FloorGrid(cols: 1, rows: 1, cellSize: cellSize,
                         originLocal: .zero, floorY: 0,
                         walkable: [[false]], fireIntensity: [[0]], occupiedBy: [[nil]])
    }

    let floorBounds = floorGrp.visualBounds(relativeTo: tabletop)
    let width = floorBounds.max.x - floorBounds.min.x
    let depth = floorBounds.max.z - floorBounds.min.z
    let cols = max(1, Int(width / cellSize))
    let rows = max(1, Int(depth / cellSize))
    let originLocal = SIMD3<Float>(floorBounds.min.x, 0, floorBounds.min.z)
    let floorY = floorBounds.max.y   // top surface of the floor slab

    // Default every cell inside the floor bounds to WALKABLE. This is essential
    // because `tabletop.scene` is still nil inside the RealityView `make` closure,
    // so a raycast-based approach would leave everything blocked. We then subtract
    // obstacles using visualBounds of Arch_grp / Object_grp descendants — that API
    // works before the entity is committed to a scene.
    var walkable = Array(repeating: Array(repeating: true, count: cols), count: rows)
    let fire = Array(repeating: Array(repeating: 0, count: cols), count: rows)
    let occupied: [[UUID?]] = Array(repeating: Array(repeating: nil, count: cols), count: rows)

    // Collect obstacle groups (walls/doors + furniture) if the USDZ exposes them.
    var obstacleRoots: [Entity] = []
    if let arch = tabletop.findEntity(named: "Arch_grp") { obstacleRoots.append(arch) }
    if let obj  = tabletop.findEntity(named: "Object_grp") { obstacleRoots.append(obj) }
    print("🧱 computeFloorGrid obstacle roots: \(obstacleRoots.map { $0.name })")

    // Only consider obstacles that actually rise above the floor — ignore thin decals
    // or entities coplanar with the floor slab.
    let minObstacleHeight: Float = 0.003   // 3 mm above floorY
    // Track the MAXIMUM single-obstacle coverage per cell (not the sum). Summing
    // over-counts when multiple furniture bboxes overlap the same cell, which was
    // causing sparsely-populated cells to be marked blocked. A cell is blocked
    // only if a single obstacle covers more than `overlapBlockFraction` of it.
    // Walls (Arch_grp) are treated as hard blockers regardless of coverage — they
    // are large, planar, and you should not place items on top of them.
    var maxCoverFrac = Array(repeating: Array(repeating: Float(0), count: cols), count: rows)
    let cellArea: Float = cellSize * cellSize
    let overlapBlockFraction: Float = 0.50   // >50% covered by a single obstacle → blocked

    func processObstacle(_ entity: Entity, groupName: String, hardBlock: Bool) {
        for descendant in entity.descendantModelEntities() {
            let b = descendant.visualBounds(relativeTo: tabletop)
            if b.max.y <= floorY + minObstacleHeight { continue }
            let minCol = max(0, Int(floor((b.min.x - originLocal.x) / cellSize)))
            let maxCol = min(cols - 1, Int(floor((b.max.x - originLocal.x) / cellSize)))
            let minRow = max(0, Int(floor((b.min.z - originLocal.z) / cellSize)))
            let maxRow = min(rows - 1, Int(floor((b.max.z - originLocal.z) / cellSize)))
            if minCol > maxCol || minRow > maxRow { continue }
            var touchedCells = 0
            for r in minRow...maxRow {
                let cellZ0 = originLocal.z + Float(r) * cellSize
                let cellZ1 = cellZ0 + cellSize
                let dz = max(0, min(b.max.z, cellZ1) - max(b.min.z, cellZ0))
                if dz <= 0 { continue }
                for c in minCol...maxCol {
                    let cellX0 = originLocal.x + Float(c) * cellSize
                    let cellX1 = cellX0 + cellSize
                    let dx = max(0, min(b.max.x, cellX1) - max(b.min.x, cellX0))
                    if dx <= 0 { continue }
                    let frac = (dx * dz) / cellArea
                    if hardBlock {
                        // Any overlap with a wall blocks the cell outright.
                        walkable[r][c] = false
                    } else if frac > maxCoverFrac[r][c] {
                        maxCoverFrac[r][c] = frac
                    }
                    touchedCells += 1
                }
            }
            print("   ⛔ [\(groupName)] '\(descendant.name)'  bounds min=\(fmt(b.min)) max=\(fmt(b.max))  touched \(touchedCells) cells")
        }
    }

    for root in obstacleRoots {
        let hardBlock = (root.name == "Arch_grp")
        processObstacle(root, groupName: root.name, hardBlock: hardBlock)
    }

    // Apply the leniency threshold to furniture (soft blockers).
    var blockedCells = 0
    for r in 0..<rows {
        for c in 0..<cols {
            if !walkable[r][c] { blockedCells += 1; continue }   // already blocked by a wall
            if maxCoverFrac[r][c] > overlapBlockFraction {
                walkable[r][c] = false
                blockedCells += 1
            }
        }
    }
    print("🧱 Cells blocked (walls + furniture > \(Int(overlapBlockFraction*100))%): \(blockedCells)/\(cols * rows)")

    let walkableCount = walkable.reduce(0) { $0 + $1.filter { $0 }.count }
    print("🟩 Floor grid: \(walkableCount)/\(cols * rows) walkable, floorY=\(floorY), size=\(cols)×\(rows)")
    print("   Floor bounds (tabletop-local): min=\(fmt(floorBounds.min))  max=\(fmt(floorBounds.max))")
    print("   originLocal=\(fmt(originLocal))  cellSize=\(cellSize)")

    // Safety net: if obstacle bounds ended up blocking almost everything (e.g. one
    // Object_grp bounding box that spans the whole floor), fall back to all-walkable.
    if walkableCount == 0 || Float(walkableCount) / Float(cols * rows) < 0.05 {
        print("⚠️ Walkability degenerate (\(walkableCount)/\(cols*rows)) — falling back to all-walkable")
        walkable = Array(repeating: Array(repeating: true, count: cols), count: rows)
    }

    return FloorGrid(cols: cols, rows: rows, cellSize: cellSize,
                     originLocal: originLocal, floorY: floorY,
                     walkable: walkable, fireIntensity: fire, occupiedBy: occupied)
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
    case .furniture: return UIColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)
    case .safety:    return UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
    case .equipment: return UIColor(red: 0.5, green: 0.8, blue: 0.4, alpha: 1.0)
    }
}

func buildPlacedItemEntity(_ item: PlacedItem) -> ModelEntity {
    // Every item is a 15 mm cube — matches the floor grid cellSize so a placed
    // item occupies exactly one cell with no visual overhang.
    let boxSize: Float = 0.015
    let mesh = MeshResource.generateBox(size: boxSize, cornerRadius: 0.002)
    let collisionShape = ShapeResource.generateBox(size: SIMD3<Float>(repeating: boxSize))
    let yLift: Float = boxSize / 2
    let matColor = colorForCategory(item.itemType.category)

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
    let layoutID: Int?
    let assetName: String?
    @Binding var screen: AppScreen
    @Environment(SceneViewModel.self) var viewModel

    @State private var scaleDelta: Float = 1.0
    @State private var rotationDelta: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var draggingItemID: UUID? = nil
    @State private var itemDragDelta: SIMD3<Float> = .zero

    // Initial tilt: ~20° toward the user so the floor plan is visible straight-on.
    // Rotating around Y then composes on top of this, revealing the 3D structure.
    private let baseTilt = simd_quatf(angle: -.pi / 9, axis: [1, 0, 0])

    var layout: LayoutConfig? { layoutID.flatMap { id in LayoutConfig.all.first { $0.id == id } } }

    var body: some View {
        RealityView { content, attachments in
            let tabletop: Entity
            if let name = assetName {
                tabletop = await loadAssetEntity(named: name)
            } else {
                tabletop = await loadRoomEntity()
            }
            tabletop.position = viewModel.tabletopTranslation
            tabletop.orientation = baseTilt
            content.add(tabletop)
            viewModel.tabletopAnchor = tabletop

            // Compute walkability grid from the USDZ semantic hierarchy (Floor_grp,
            // Arch_grp, Object_grp). Must run AFTER content.add(tabletop).
            viewModel.floorGrid = computeFloorGrid(tabletop: tabletop)

            // Billboarded palette to the right of the tabletop.
            if let palette = attachments.entity(for: "palette") {
                palette.name = "paletteAttachment"
                palette.position = [0.25, 0.02, 0.05]
                palette.scale = SIMD3(repeating: 1.0)   // 1200pt frame at 1x ≈ 0.88m — fits 1m tall window
                palette.components.set(BillboardComponent())
                content.add(palette)
            }

            // Billboarded nav bar hovering above the tabletop.
            if let navbar = attachments.entity(for: "navbar") {
                navbar.name = "navbarAttachment"
                navbar.position = [-0.1, 0.42, 0.05]
                navbar.scale = SIMD3(repeating: 2.0)    // easy to read
                navbar.components.set(BillboardComponent())
                content.add(navbar)
            }
        } update: { content, _ in
            guard let tabletop = content.entities.first(where: { $0.name == "tabletopGroup" }) else { return }
            tabletop.position = viewModel.tabletopTranslation
            let effectiveScale = viewModel.tabletopScale * scaleDelta
            tabletop.scale    = SIMD3(repeating: effectiveScale)
            // Compose: baseTilt (fixed initial pose) → committed user rotation → in-progress gesture delta
            tabletop.orientation = rotationDelta * viewModel.tabletopRotation * baseTilt

            // Push palette + navbar outward as the tabletop grows so they don't overlap.
            // Palette moves horizontally with room size. Navbar only nudges slightly upward
            // (room is thin) — additive formula keeps it inside the window at any scale.
            let base = viewModel.tabletopTranslation
            let roomHalfWidth: Float = 0.2       // targetSize 0.4 / 2
            let roomHalfHeight: Float = 0.05     // approx (room is thin)
            let paletteMargin: Float = 0.30      // clearance from room right edge
            // Navbar sits well above the room. The tilted, user-scaled room can reach
            // ~y=0.20 at scale 2.5 (roomHalfHeight + tilt-induced rise from the ~1m
            // long floor); a large margin keeps the navbar clear at any orientation.
            let navbarMargin: Float = 0.38
            // Safe bounds — palette is 1.8x scaled (~19cm half-width), navbar 2.0x
            // (~22cm half-width, ~4cm half-height). Window is ±1.1 x ±0.5 x ±0.75.
            let paletteMaxX: Float = 0.88        // 0.88 + 0.19 = 1.07m (inside 1.1m wall)
            let navbarMaxY: Float = 0.46         // 0.46 + 0.04 = 0.50m (at 0.5m top)
            if let palette = content.entities.first(where: { $0.name == "paletteAttachment" }) {
                let desiredX = base.x + roomHalfWidth * effectiveScale + paletteMargin
                palette.position = [min(desiredX, paletteMaxX), 0.02, 0.05]
            }
            if let navbar = content.entities.first(where: { $0.name == "navbarAttachment" }) {
                let desiredY = base.y + roomHalfHeight * effectiveScale + navbarMargin
                navbar.position = [base.x, min(desiredY, navbarMaxY), 0.05]
            }

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
        .simultaneousGesture(doubleTapDeleteGesture)
        .simultaneousGesture(longPressDeleteGesture)
        .simultaneousGesture(itemDragGesture)
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
                viewModel.tabletopScale = max(0.3, min(6.0, viewModel.tabletopScale))
                scaleDelta = 1.0
            }
    }

    /// Two-hand twist gesture. Free-axis (no constraint), so the room can yaw, pitch,
    /// and roll on real AVP hardware. Applies the composed orientation directly to
    /// the tabletop inside `.onChanged` for immediate per-frame feedback (bypasses
    /// any RealityView update-closure latency).
    private var rotateGesture: some Gesture {
        RotateGesture3D()   // NO axis constraint — free 3D rotation
            .targetedToAnyEntity()
            .onChanged { value in
                let delta = quatFromRotation3D(value.rotation)
                rotationDelta = delta
                // Apply immediately so the entity visibly rotates during the gesture.
                if let tabletop = viewModel.tabletopAnchor {
                    tabletop.orientation = simd_normalize(delta * viewModel.tabletopRotation * baseTilt)
                }
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
                let delta = yaw * pitch
                rotationDelta = delta
                if let tabletop = viewModel.tabletopAnchor {
                    tabletop.orientation = simd_normalize(delta * viewModel.tabletopRotation * baseTilt)
                }
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

    /// Long-press (0.5 s) a placed item to delete it. Provided as an alternative to
    /// double-tap because the visionOS simulator does not reliably deliver
    /// `SpatialTapGesture(count: 2)` — long-press works there and on device.
    private var longPressDeleteGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .targetedToAnyEntity()
            .onEnded { value in
                guard let component = value.entity.components[PlacedItemComponent.self] else { return }
                let itemID = component.itemID
                print("🗑️ Long-press delete: \(itemID.uuidString.prefix(6))")
                if let anchor = viewModel.tabletopAnchor,
                   let entity = anchor.findEntity(named: "placed_\(itemID.uuidString)") {
                    entity.removeFromParent()
                }
                viewModel.removeItem(id: itemID)
            }
    }

    /// Double-tap a placed item to delete it from the layout. Frees the underlying
    /// grid cell so a new item can be placed there afterward.
    private var doubleTapDeleteGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToAnyEntity()
            .onEnded { value in
                guard let component = value.entity.components[PlacedItemComponent.self] else { return }
                let itemID = component.itemID
                print("🗑️ Double-tap delete: \(itemID.uuidString.prefix(6))")
                if let anchor = viewModel.tabletopAnchor,
                   let entity = anchor.findEntity(named: "placed_\(itemID.uuidString)") {
                    entity.removeFromParent()
                }
                viewModel.removeItem(id: itemID)   // frees the cell too
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

                let originalLift = entity.position.y - viewModel.placedItems[idx].position.y
                let oldPos = viewModel.placedItems[idx].position

                // Compute the old cell so we can free it before checking the new one
                let oldCell = viewModel.floorGrid?.cellAt(local: oldPos)

                // Temporarily free the old cell so isFree correctly ignores this item
                if let old = oldCell {
                    viewModel.floorGrid?.free(col: old.col, row: old.row)
                }

                if let grid = viewModel.floorGrid,
                   let (col, row) = grid.cellAt(local: candidate),
                   grid.isWalkable(col: col, row: row),
                   grid.isFree(col: col, row: row) {
                    // Accept: occupy new cell, update model + entity position
                    viewModel.floorGrid?.occupy(col: col, row: row, itemID: itemID)
                    let snapped = grid.cellCenterLocal(col: col, row: row)
                    viewModel.placedItems[idx].position = snapped
                    entity.position = SIMD3(snapped.x, snapped.y + originalLift, snapped.z)
                } else {
                    // Reject: re-occupy old cell, revert entity to original position
                    if let old = oldCell {
                        viewModel.floorGrid?.occupy(col: old.col, row: old.row, itemID: itemID)
                    }
                    entity.position = SIMD3(oldPos.x, oldPos.y + originalLift, oldPos.z)
                    print("🚫 Drop rejected — outside room, blocked, or cell occupied")
                }
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

        // Standard tap-to-place for ALL items (including cone).
        guard let itemType = viewModel.selectedItemType,
              let tabletop = viewModel.tabletopAnchor,
              tappedEntity.name != "paletteAttachment",
              !isDescendant(of: "paletteAttachment", entity: tappedEntity) else { return }

        let worldLocation = value.convert(value.location3D, from: .local, to: .scene)
        let localLocation = tabletop.convert(position: worldLocation, from: nil)

        print("👆 Tap on entity '\(tappedEntity.name)'  world=\(fmt(worldLocation))  local=\(fmt(localLocation))")

        // Placement rules:
        //   • Tap must land inside the floor grid bounds
        //   • Cell must be walkable (not on a wall from Arch_grp or furniture from Object_grp)
        //   • Cell must be free (not already occupied by another placed item)
        guard let grid = viewModel.floorGrid else {
            print("🚫 No floor grid built yet — rejected")
            return
        }
        print("   Grid: \(grid.cols)×\(grid.rows) cellSize=\(grid.cellSize)  originLocal=\(fmt(grid.originLocal))  floorY=\(grid.floorY)  walkableCount=\(grid.walkableCount)/\(grid.cols*grid.rows)")
        print("   Grid X range: [\(grid.originLocal.x) … \(grid.originLocal.x + Float(grid.cols) * grid.cellSize)]  Z range: [\(grid.originLocal.z) … \(grid.originLocal.z + Float(grid.rows) * grid.cellSize)]")
        // Auto-snap: if the exact tapped cell is blocked/occupied (or the tap landed
        // just outside the grid), BFS outward to the nearest free walkable cell.
        // This makes placement forgiving in dense layouts where most cells sit under
        // furniture bounding boxes.
        guard let (targetCol, targetRow) = grid.nearestFreeWalkableCell(to: localLocation) else {
            print("🚫 No free walkable cell within search radius — rejected")
            return
        }
        if let tapped = grid.cellAt(local: localLocation) {
            print("   Tapped cell (col=\(tapped.col), row=\(tapped.row))  walkable=\(grid.walkable[tapped.row][tapped.col])  occupiedBy=\(String(describing: grid.occupiedBy[tapped.row][tapped.col]))")
            dumpNeighborhood(grid: grid, col: tapped.col, row: tapped.row, radius: 3)
            if tapped.col != targetCol || tapped.row != targetRow {
                let dc = targetCol - tapped.col
                let dr = targetRow - tapped.row
                print("   ↪️ Auto-snapped to nearest free cell (col=\(targetCol), row=\(targetRow))  Δ=(\(dc), \(dr))")
            }
        } else {
            print("   Tap outside grid — snapped to (col=\(targetCol), row=\(targetRow))")
        }

        let snappedLocal = grid.cellCenterLocal(col: targetCol, row: targetRow)
        let placed = viewModel.placeItem(itemType, at: snappedLocal)
        viewModel.floorGrid?.occupy(col: targetCol, row: targetRow, itemID: placed.id)
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
        viewModel.tabletopScale = 2.5
        viewModel.tabletopRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }
}
