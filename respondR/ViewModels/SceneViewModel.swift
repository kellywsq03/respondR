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

    var phase1AssetsDownloaded = false
    var preloadedAssetNames: [String] = []

    // Left of center (leaves room for trailing panel), below center (tabletop feel), forward toward viewer
    var tabletopTranslation: SIMD3<Float> = [-0.1, -0.1, 0.05]
    var tabletopScale: Float = 2.5
    var tabletopRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])

    func preloadPhase1Assets() async throws {
        preloadedAssetNames = try await SupabaseAssetLoader.downloadAllUSDZAssets()
        phase1AssetsDownloaded = true
    }

    func placeItem(_ type: ItemType, at localPosition: SIMD3<Float>) -> PlacedItem {
        let item = PlacedItem(id: UUID(), itemType: type, position: localPosition)
        placedItems.append(item)
        selectedItemType = nil
        return item
    }

    func removeItem(id: UUID) {
        // Free the grid cell the item was occupying so a new item can be placed there.
        if let item = placedItems.first(where: { $0.id == id }),
           let cell = floorGrid?.cellAt(local: item.position) {
            floorGrid?.free(col: cell.col, row: cell.row)
        }
        placedItems.removeAll { $0.id == id }
        if selectedPlacedItemID == id {
            selectedPlacedItemID = nil
        }
    }
}
