import Foundation
import RealityKit

enum ItemCategory: String, CaseIterable {
    case furniture = "Furniture"
    case appliances = "Appliances"
    case belongings = "Belongings"
}

struct ItemType: Equatable {
    let name: String
    let sfSymbol: String
    let category: ItemCategory

    static let allTypes: [ItemType] = [
        ItemType(name: "Couch",        sfSymbol: "rectangle.split.3x1.fill", category: .furniture),
        ItemType(name: "Table",        sfSymbol: "tablecells",               category: .furniture),
        ItemType(name: "Chair",        sfSymbol: "chair",                    category: .furniture),
        ItemType(name: "Bed",          sfSymbol: "cone.fill",                category: .furniture),
        ItemType(name: "Stove",        sfSymbol: "flame.fill",               category: .appliances),
        ItemType(name: "Refrigerator", sfSymbol: "refrigerator.fill",        category: .appliances),
        ItemType(name: "Washer",       sfSymbol: "washer.fill",              category: .appliances),
        ItemType(name: "Bag",          sfSymbol: "bag.fill",                 category: .belongings),
        ItemType(name: "Box",          sfSymbol: "shippingbox.fill",         category: .belongings),
        ItemType(name: "Bicycle",      sfSymbol: "bicycle",                  category: .belongings),
    ]
}

struct PlacedItem: Identifiable {
    let id: UUID
    let itemType: ItemType
    var position: SIMD3<Float>
}

struct PlacedItemComponent: Component {
    var itemID: UUID
}
