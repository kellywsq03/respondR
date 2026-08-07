import SwiftUI
import RealityKit

// MARK: - Tabletop Factory

func buildTabletop(layout: LayoutConfig) -> Entity {
    let group = Entity()
    group.name = "tabletopGroup"

    // Floor surface — light blueprint tint
    let floorMesh = MeshResource.generateBox(
        width: layout.floorSize.x,
        height: 0.004,
        depth: layout.floorSize.y,
        cornerRadius: 0.004
    )
    var floorMat = SimpleMaterial()
    floorMat.color = .init(tint: .init(red: 0.90, green: 0.93, blue: 0.97, alpha: 1.0))
    floorMat.roughness = .float(0.95)
    floorMat.metallic = .float(0.0)
    let floorEntity = ModelEntity(mesh: floorMesh, materials: [floorMat])
    floorEntity.name = "floorPlane"
    floorEntity.collision = CollisionComponent(
        shapes: [.generateBox(width: layout.floorSize.x, height: 0.004, depth: layout.floorSize.y)]
    )
    floorEntity.components.set(InputTargetComponent())
    group.addChild(floorEntity)

    addFloorGrid(to: group, floorSize: layout.floorSize)
    addPlaceholderFrame(to: group, floorSize: layout.floorSize)

    // Walls — dark charcoal, readable from any angle
    var wallMat = SimpleMaterial()
    wallMat.color = .init(tint: .init(red: 0.18, green: 0.22, blue: 0.30, alpha: 1.0))
    wallMat.roughness = .float(0.9)

    for wall in layout.walls {
        let wallMesh = MeshResource.generateBox(
            width: wall.size.x,
            height: wall.size.y,
            depth: wall.size.z
        )
        let wallEntity = ModelEntity(mesh: wallMesh, materials: [wallMat])
        wallEntity.position = wall.position
        wallEntity.orientation = simd_quatf(angle: wall.rotation, axis: [0, 1, 0])
        group.addChild(wallEntity)
    }

    return group
}

/// Bold 3D frame: base border strips + tall corner posts + top connecting rails.
/// Together these make the placeholder clearly visible from any angle — especially
/// from the front before the user tilts down to see the floor plan.
private func addPlaceholderFrame(to parent: Entity, floorSize: SIMD2<Float>) {
    let frameColor = UIColor(red: 0.20, green: 0.48, blue: 1.00, alpha: 1.0)

    var mat = SimpleMaterial()
    mat.color = .init(tint: frameColor)
    mat.roughness = .float(0.5)
    mat.metallic  = .float(0.2)

    let halfX = floorSize.x / 2
    let halfZ = floorSize.y / 2

    // ── Base border — thick strips at floor level ──
    let bH: Float = 0.012
    let bT: Float = 0.018
    let bY: Float = bH / 2
    let baseBorders: [(SIMD3<Float>, SIMD3<Float>)] = [
        ([0,      bY, -halfZ], [floorSize.x + bT, bH, bT]),
        ([0,      bY,  halfZ], [floorSize.x + bT, bH, bT]),
        ([-halfX, bY,  0],     [bT, bH, floorSize.y]),
        ([ halfX, bY,  0],     [bT, bH, floorSize.y]),
    ]
    for (pos, size) in baseBorders {
        let e = ModelEntity(
            mesh: MeshResource.generateBox(width: size.x, height: size.y, depth: size.z),
            materials: [mat]
        )
        e.position = pos
        parent.addChild(e)
    }

    // ── Corner posts — the tallest elements, visible from eye level ──
    let postSide: Float = 0.020   // 2 cm square
    let postH:    Float = 0.200   // 20 cm — clearly above the walls, visible from the front
    let postMesh = MeshResource.generateBox(width: postSide, height: postH, depth: postSide)
    let postY = postH / 2
    let postPositions: [SIMD3<Float>] = [
        [-halfX, postY, -halfZ],
        [ halfX, postY, -halfZ],
        [-halfX, postY,  halfZ],
        [ halfX, postY,  halfZ],
    ]
    for pos in postPositions {
        let e = ModelEntity(mesh: postMesh, materials: [mat])
        e.position = pos
        parent.addChild(e)
    }

    // ── Top rails — connect post tops, outline the footprint at 20 cm height ──
    var railMat = SimpleMaterial()
    railMat.color = .init(tint: frameColor.withAlphaComponent(0.7))
    railMat.roughness = .float(0.6)
    let rH: Float = 0.010
    let rT: Float = 0.010
    let rY: Float = postH
    let rails: [(SIMD3<Float>, SIMD3<Float>)] = [
        ([0,      rY, -halfZ], [floorSize.x, rH, rT]),
        ([0,      rY,  halfZ], [floorSize.x, rH, rT]),
        ([-halfX, rY,  0],     [rT, rH, floorSize.y]),
        ([ halfX, rY,  0],     [rT, rH, floorSize.y]),
    ]
    for (pos, size) in rails {
        let e = ModelEntity(
            mesh: MeshResource.generateBox(width: size.x, height: size.y, depth: size.z),
            materials: [railMat]
        )
        e.position = pos
        parent.addChild(e)
    }
}

private func addFloorGrid(to parent: Entity, floorSize: SIMD2<Float>) {
    var gridMat = SimpleMaterial()
    gridMat.color = .init(tint: .init(red: 0.60, green: 0.72, blue: 0.90, alpha: 1.0))
    gridMat.roughness = .float(1.0)

    let lineH: Float = 0.001
    let lineT: Float = 0.002
    let step:  Float = 0.06
    let yPos:  Float = 0.003

    var x = -floorSize.x / 2 + step
    while x < floorSize.x / 2 {
        let e = ModelEntity(
            mesh: MeshResource.generateBox(width: lineT, height: lineH, depth: floorSize.y),
            materials: [gridMat]
        )
        e.position = [x, yPos, 0]
        parent.addChild(e)
        x += step
    }
    var z = -floorSize.y / 2 + step
    while z < floorSize.y / 2 {
        let e = ModelEntity(
            mesh: MeshResource.generateBox(width: floorSize.x, height: lineH, depth: lineT),
            materials: [gridMat]
        )
        e.position = [0, yPos, z]
        parent.addChild(e)
        z += step
    }
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

    @State private var dragDelta: SIMD3<Float> = .zero
    @State private var scaleDelta: Float = 1.0
    @State private var rotationDelta: Float = 0.0

    // Initial tilt: ~20° toward the user so the floor plan is visible straight-on.
    // Rotating around Y then composes on top of this, revealing the 3D structure.
    private let baseTilt = simd_quatf(angle: -.pi / 9, axis: [1, 0, 0])

    var layout: LayoutConfig { LayoutConfig.all.first { $0.id == layoutID }! }

    var body: some View {
        RealityView { content in
            let tabletop = buildTabletop(layout: layout)
            tabletop.position = viewModel.tabletopTranslation
            tabletop.orientation = baseTilt
            content.add(tabletop)
            viewModel.tabletopAnchor = tabletop
        } update: { content in
            guard let tabletop = content.entities.first(where: { $0.name == "tabletopGroup" }) else { return }
            tabletop.position = viewModel.tabletopTranslation + dragDelta
            tabletop.scale    = SIMD3(repeating: viewModel.tabletopScale * scaleDelta)
            let yRot = simd_quatf(angle: viewModel.tabletopRotationY + rotationDelta, axis: [0, 1, 0])
            tabletop.orientation = yRot * baseTilt
        }
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(rotateGesture)
        .simultaneousGesture(tapGesture)
        // Nav bar: contentAlignment .bottom means the bar's bottom edge sits at the
        // window's top edge — the entire bar floats above the window volume.
        // The trailing panel (centered on the right edge) has its top above the window's
        // top edge too, so both "Items" and the nav bar end up at the same height.
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
        // Item palette — to the right of the window, clear of the layout
        .ornament(attachmentAnchor: .scene(.trailing)) {
            ItemPaletteView()
                .environment(viewModel)
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let t = value.translation3D
                dragDelta = SIMD3(Float(t.x), Float(t.y), Float(t.z))
            }
            .onEnded { value in
                let t = value.translation3D
                viewModel.tabletopTranslation += SIMD3(Float(t.x), Float(t.y), Float(t.z))
                dragDelta = .zero
            }
    }

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

        guard tappedEntity.name == "floorPlane",
              let itemType = viewModel.selectedItemType,
              let tabletop = viewModel.tabletopAnchor else { return }

        let worldLocation = value.convert(value.location3D, from: .local, to: .scene)
        let localLocation = tabletop.convert(position: worldLocation, from: nil)

        let placed = viewModel.placeItem(itemType, at: localLocation)
        let placedEntity = buildPlacedItemEntity(placed)
        tabletop.addChild(placedEntity)
    }

    // MARK: - Helpers

    private func resetViewModel() {
        viewModel.tabletopAnchor = nil
        viewModel.selectedItemType = nil
        viewModel.selectedPlacedItemID = nil
        viewModel.placedItems = []
        viewModel.tabletopTranslation = [-0.2, -0.15, 0.0]
        viewModel.tabletopScale = 1.0
        viewModel.tabletopRotationY = 0.0
    }
}
