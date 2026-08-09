import Foundation
import RealityKit

enum ItemCategory: String, CaseIterable {
    case furniture = "Furniture"
    case safety    = "Safety"
    case equipment = "Equipment"
}

struct ItemType: Equatable {
    let name: String
    let sfSymbol: String
    let category: ItemCategory

    static let allTypes: [ItemType] = [
        // Furniture
        ItemType(name: "Office Chair",     sfSymbol: "chair.lounge.fill",         category: .furniture),
        ItemType(name: "Desk",             sfSymbol: "tablecells",                category: .furniture),
        ItemType(name: "Conference Table", sfSymbol: "rectangle.split.3x1.fill",  category: .furniture),
        ItemType(name: "Bookshelf",        sfSymbol: "books.vertical.fill",       category: .furniture),
        ItemType(name: "Filing Cabinet",   sfSymbol: "archivebox.fill",           category: .furniture),
        ItemType(name: "Whiteboard",       sfSymbol: "rectangle.dashed",          category: .furniture),

        // Safety
        ItemType(name: "Fire Extinguisher", sfSymbol: "flame.circle.fill",        category: .safety),
        ItemType(name: "Smoke Detector",    sfSymbol: "sensor.fill",              category: .safety),
        ItemType(name: "First Aid Kit",     sfSymbol: "cross.case.fill",          category: .safety),
        ItemType(name: "Emergency Exit",    sfSymbol: "door.right.hand.open",     category: .safety),
        ItemType(name: "Sprinkler",         sfSymbol: "drop.fill",                category: .safety),
        ItemType(name: "Alarm",             sfSymbol: "bell.fill",                category: .safety),

        // Equipment
        ItemType(name: "Monitor",  sfSymbol: "display",                     category: .equipment),
        ItemType(name: "Laptop",   sfSymbol: "laptopcomputer",              category: .equipment),
        ItemType(name: "Printer",  sfSymbol: "printer.fill",                category: .equipment),
        ItemType(name: "Phone",    sfSymbol: "phone.fill",                  category: .equipment),
        ItemType(name: "Projector", sfSymbol: "video.fill",                 category: .equipment),
        ItemType(name: "Server",   sfSymbol: "externaldrive.fill",          category: .equipment),
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
