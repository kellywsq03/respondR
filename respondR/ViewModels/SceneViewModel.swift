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

    // Left of center (panel space), below window center (tabletop feel), z=0 (window mid-depth)
    var tabletopTranslation: SIMD3<Float> = [-0.2, -0.15, 0.0]
    var tabletopScale: Float = 1.0
    var tabletopRotationY: Float = 0.0

    func placeItem(_ type: ItemType, at localPosition: SIMD3<Float>) -> PlacedItem {
        let item = PlacedItem(id: UUID(), itemType: type, position: localPosition)
        placedItems.append(item)
        selectedItemType = nil
        return item
    }

    func removeItem(id: UUID) {
        placedItems.removeAll { $0.id == id }
        if selectedPlacedItemID == id {
            selectedPlacedItemID = nil
        }
    }
}
