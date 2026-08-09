import Foundation
import RealityKit
import Observation

@MainActor
@Observable
class SceneViewModel {
    var selectedItemType: ItemType? = nil
    var placedItems: [PlacedItem] = []
    var selectedPlacedItemID: UUID? = nil

    weak var tabletopAnchor: Entity? = nil
    var floorGrid: FloorGrid? = nil

    // Left of center (leaves room for trailing panel), below center (tabletop feel), forward toward viewer
    var tabletopTranslation: SIMD3<Float> = [-0.1, -0.1, 0.05]
    var tabletopScale: Float = 2.5
    var tabletopRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])

    /// A small, bounded update loop makes an ignition point visibly expand without
    /// allowing a large layout to fill with markers all at once.
    private let fireSpreadIntervalNanoseconds: UInt64 = 700_000_000
    private let fireSpreadFanoutPerSource = 3
    private let maximumFireMarkersPerSource = 240
    private var fireSpreadTask: Task<Void, Never>? = nil

    func placeItem(_ type: ItemType, at localPosition: SIMD3<Float>) -> PlacedItem {
        let id = UUID()
        let item = PlacedItem(
            id: id,
            itemType: type,
            position: localPosition,
            fireSourceID: type.isFire ? id : nil
        )
        placedItems.append(item)
        selectedItemType = nil
        return item
    }

    func startFireSpread() {
        guard fireSpreadTask == nil else { return }
        fireSpreadTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.fireSpreadIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                self.spreadFireOneStep()
            }
        }
    }

    func stopFireSpread() {
        fireSpreadTask?.cancel()
        fireSpreadTask = nil
    }

    /// Expands each user-placed ignition front by a few neighboring cells. The
    /// source-distance ordering keeps growth moving outward from the initial point;
    /// walls, furniture, and occupied cells remain impassable.
    private func spreadFireOneStep() {
        guard var grid = floorGrid, let tabletop = tabletopAnchor else {
            stopFireSpread()
            return
        }

        let sources = placedItems.filter { $0.itemType.isFire && $0.fireSourceID == $0.id }
        guard !sources.isEmpty else {
            stopFireSpread()
            return
        }

        for source in sources {
            let sourceFires = placedItems.filter { $0.fireSourceID == source.id }
            guard sourceFires.count < maximumFireMarkersPerSource,
                  let sourceCell = grid.cellAt(local: source.position) else { continue }

            var candidateKeys = Set<Int>()
            for fire in sourceFires {
                guard let cell = grid.cellAt(local: fire.position) else { continue }
                for rowDelta in -1...1 {
                    for colDelta in -1...1 where colDelta != 0 || rowDelta != 0 {
                        let col = cell.col + colDelta
                        let row = cell.row + rowDelta
                        guard grid.isWalkable(col: col, row: row), grid.isFree(col: col, row: row) else { continue }
                        candidateKeys.insert(row * grid.cols + col)
                    }
                }
            }

            let candidates = candidateKeys
                .map { (col: $0 % grid.cols, row: $0 / grid.cols) }
                .sorted {
                    let lhsDistance = ($0.col - sourceCell.col) * ($0.col - sourceCell.col)
                        + ($0.row - sourceCell.row) * ($0.row - sourceCell.row)
                    let rhsDistance = ($1.col - sourceCell.col) * ($1.col - sourceCell.col)
                        + ($1.row - sourceCell.row) * ($1.row - sourceCell.row)
                    if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                    if $0.row != $1.row { return $0.row < $1.row }
                    return $0.col < $1.col
                }

            let remainingCapacity = maximumFireMarkersPerSource - sourceFires.count
            for candidate in candidates.prefix(min(fireSpreadFanoutPerSource, remainingCapacity)) {
                let fire = PlacedItem(
                    id: UUID(),
                    itemType: .fire,
                    position: grid.cellCenterLocal(col: candidate.col, row: candidate.row),
                    fireSourceID: source.id
                )
                placedItems.append(fire)
                grid.occupy(col: candidate.col, row: candidate.row, itemID: fire.id)
                tabletop.addChild(buildPlacedItemEntity(fire))
            }
        }
        floorGrid = grid
    }

    func removeItem(id: UUID) {
        guard let item = placedItems.first(where: { $0.id == id }) else { return }
        // Removing an ignition point also removes the fire it originated. This keeps
        // the layout and its grid occupancy in sync when a scenario is edited.
        let idsToRemove: Set<UUID>
        if item.itemType.isFire && item.fireSourceID == item.id {
            idsToRemove = Set(placedItems.compactMap { $0.fireSourceID == id ? $0.id : nil })
        } else {
            idsToRemove = [id]
        }

        for removedItem in placedItems where idsToRemove.contains(removedItem.id) {
            if let cell = floorGrid?.cellAt(local: removedItem.position) {
                floorGrid?.free(col: cell.col, row: cell.row)
            }
            tabletopAnchor?.findEntity(named: "placed_\(removedItem.id.uuidString)")?.removeFromParent()
        }
        placedItems.removeAll { idsToRemove.contains($0.id) }
        if let selectedID = selectedPlacedItemID, idsToRemove.contains(selectedID) {
            selectedPlacedItemID = nil
        }
        if !placedItems.contains(where: { $0.itemType.isFire && $0.fireSourceID == $0.id }) {
            stopFireSpread()
        }
    }
}
