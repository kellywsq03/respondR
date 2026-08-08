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

    var walkable = Array(repeating: Array(repeating: false, count: cols), count: rows)
    let fire = Array(repeating: Array(repeating: 0, count: cols), count: rows)

    guard let scene = tabletop.scene else {
        print("⚠️ computeFloorGrid: tabletop not yet in scene, returning empty grid")
        return FloorGrid(cols: cols, rows: rows, cellSize: cellSize,
                         originLocal: origin, walkable: walkable, fireIntensity: fire)
    }

    let floorTolerance: Float = 0.015
    let rayHeight: Float = 0.4

    for row in 0..<rows {
        for col in 0..<cols {
            let localCenter = SIMD3<Float>(
                origin.x + (Float(col) + 0.5) * cellSize,
                rayHeight,
                origin.z + (Float(row) + 0.5) * cellSize
            )
            let originWorld = tabletop.convert(position: localCenter, to: nil)
            let endLocal    = SIMD3<Float>(localCenter.x, -0.1, localCenter.z)
            let endWorld    = tabletop.convert(position: endLocal, to: nil)

            let hits = scene.raycast(from: originWorld, to: endWorld)
            let topmostY = hits
                .map { tabletop.convert(position: $0.position, from: nil).y }
                .max() ?? -Float.infinity

            walkable[row][col] = abs(topmostY - 0.0) < floorTolerance
        }
    }

    let grid = FloorGrid(cols: cols, rows: rows, cellSize: cellSize,
                         originLocal: origin, walkable: walkable, fireIntensity: fire)
    print("🟩 Floor grid: \(grid.walkableCount)/\(cols * rows) walkable cells (\(cols)×\(rows))")
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
    let mesh = MeshResource.generateBox(size: 0.028, cornerRadius: 0.004)
    var mat = SimpleMaterial()
    mat.color = .init(tint: colorForCategory(item.itemType.category))
    mat.roughness = .float(0.6)
    let entity = ModelEntity(mesh: mesh, materials: [mat])
    entity.name = "placed_\(item.id.uuidString)"
    entity.position = SIMD3(item.position.x, 0.017, item.position.z)
    entity.collision = CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(repeating: 0.028))])
    entity.components.set(InputTargetComponent())
    entity.components.set(PlacedItemComponent(itemID: item.id))
    return entity
}

// MARK: - Scene View

struct SceneView: View {
    let layoutID: Int
    @Binding var screen: AppScreen
    @Environment(SceneViewModel.self) var viewModel

    @State private var scaleDelta: Float = 1.0
    @State private var rotationDelta: Float = 0.0

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

            // Compute walkability grid from the loaded room, then add visual overlay.
            // Must run AFTER content.add(tabletop) so tabletop.scene is available for raycasts.
            if let room = tabletop.findEntity(named: "roomModel") {
                let boundsLocal = room.visualBounds(relativeTo: tabletop)
                let grid = computeFloorGrid(tabletop: tabletop, roomBoundsLocal: boundsLocal)
                viewModel.floorGrid = grid
                let overlay = buildGridOverlay(grid)
                tabletop.addChild(overlay)
            }

            // Billboarded palette: fixed position to the right of the tabletop,
            // rotates around Y to always face the user.
            if let palette = attachments.entity(for: "palette") {
                palette.name = "paletteAttachment"
                palette.position = [0.65, 0.05, 0.2]
                palette.components.set(BillboardComponent())
                content.add(palette)
            }
        } update: { content, _ in
            guard let tabletop = content.entities.first(where: { $0.name == "tabletopGroup" }) else { return }
            tabletop.position = viewModel.tabletopTranslation
            tabletop.scale    = SIMD3(repeating: viewModel.tabletopScale * scaleDelta)
            let yRot = simd_quatf(angle: viewModel.tabletopRotationY + rotationDelta, axis: [0, 1, 0])
            tabletop.orientation = yRot * baseTilt
        } attachments: {
            Attachment(id: "palette") {
                ItemPaletteView()
                    .environment(viewModel)
            }
        }
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(rotateGesture)
        .simultaneousGesture(tapGesture)
        .ornament(attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
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

    private var rotateGesture: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToAnyEntity()
            .onChanged { value in
                rotationDelta = Float(value.rotation.angle.radians)
            }
            .onEnded { value in
                viewModel.tabletopRotationY += Float(value.rotation.angle.radians)
                rotationDelta = 0.0
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                handleTap(value: value)
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

        guard let itemType = viewModel.selectedItemType,
              let tabletop = viewModel.tabletopAnchor,
              let grid = viewModel.floorGrid,
              tappedEntity.name != "paletteAttachment",
              !isDescendant(of: "paletteAttachment", entity: tappedEntity) else { return }

        let worldLocation = value.convert(value.location3D, from: .local, to: .scene)
        let localLocation = tabletop.convert(position: worldLocation, from: nil)

        // Snap to nearest cell + reject if cell is blocked
        guard let (col, row) = grid.cellAt(local: localLocation),
              grid.isWalkable(col: col, row: row) else {
            print("🚫 Tap outside grid or on blocked cell")
            return
        }
        let snappedLocal = grid.cellCenterLocal(col: col, row: row)

        let placed = viewModel.placeItem(itemType, at: snappedLocal)
        let placedEntity = buildPlacedItemEntity(placed)
        tabletop.addChild(placedEntity)
    }

    // MARK: - Helpers

    private func resetViewModel() {
        viewModel.tabletopAnchor = nil
        viewModel.floorGrid = nil
        viewModel.selectedItemType = nil
        viewModel.selectedPlacedItemID = nil
        viewModel.placedItems = []
        viewModel.tabletopTranslation = [-0.15, -0.15, 0.15]
        viewModel.tabletopScale = 1.0
        viewModel.tabletopRotationY = 0.0
    }
}
