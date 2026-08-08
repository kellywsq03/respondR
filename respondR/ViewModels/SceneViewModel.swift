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
