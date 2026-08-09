import Foundation
import RealityKit

enum ItemCategory: String, CaseIterable {
    case furniture = "Furniture"
    case safety    = "Safety"
    case equipment = "Equipment"
    case hazard    = "Hazards"
}

/// Determines how a placed object responds after fire reaches it.
enum CombustionMaterial: String, Equatable {
    case wood = "Wood"
    case plastic = "Plastic"
    case metal = "Metal"
    case fireproof = "Fireproof"

    /// Relative to the scenario's base burn time. `nil` means the item cannot be
    /// consumed by this phase's fire simulation.
    func burnDuration(base: TimeInterval) -> TimeInterval? {
        switch self {
        case .wood:      return base * 0.5
        case .plastic:   return base * 0.75
        case .metal:     return base * 2.0
        case .fireproof: return nil
        }
    }
}

struct ItemType: Equatable {
    let name: String
    let sfSymbol: String
    let category: ItemCategory
    let combustionMaterial: CombustionMaterial?
    let usdzResourceName: String?

    static let fire = ItemType(name: "Fire", sfSymbol: "flame.fill", category: .hazard, combustionMaterial: nil, usdzResourceName: "Flame")

    var isFire: Bool { self == Self.fire }

    static let allTypes: [ItemType] = [
        // Hazards
        // A fire is an initial ignition point; phase 1 expands it across the
        // walkable floor over time.
        .fire,

        // Furniture
        ItemType(name: "Office Chair",     sfSymbol: "chair.lounge.fill",         category: .furniture, combustionMaterial: .wood, usdzResourceName: nil),
        ItemType(name: "Desk",             sfSymbol: "tablecells",                category: .furniture, combustionMaterial: .wood, usdzResourceName: nil),
        ItemType(name: "Conference Table", sfSymbol: "rectangle.split.3x1.fill",  category: .furniture, combustionMaterial: .wood, usdzResourceName: nil),
        ItemType(name: "Bookshelf",        sfSymbol: "books.vertical.fill",       category: .furniture, combustionMaterial: .wood, usdzResourceName: nil),
        ItemType(name: "Filing Cabinet",   sfSymbol: "archivebox.fill",           category: .furniture, combustionMaterial: .metal, usdzResourceName: "filingcabinet"),
        ItemType(name: "Wardrobe",         sfSymbol: "cabinet.fill",              category: .furniture, combustionMaterial: .wood, usdzResourceName: "wardrobe"),
        ItemType(name: "Basin",            sfSymbol: "sink.fill",                 category: .furniture, combustionMaterial: .fireproof, usdzResourceName: "basin"),
        ItemType(name: "Whiteboard",       sfSymbol: "rectangle.dashed",          category: .furniture, combustionMaterial: .fireproof, usdzResourceName: nil),

        // Safety
        ItemType(name: "Fire Extinguisher", sfSymbol: "flame.circle.fill",        category: .safety, combustionMaterial: .metal, usdzResourceName: nil),
        ItemType(name: "Smoke Detector",    sfSymbol: "sensor.fill",              category: .safety, combustionMaterial: .fireproof, usdzResourceName: nil),
        ItemType(name: "First Aid Kit",     sfSymbol: "cross.case.fill",          category: .safety, combustionMaterial: .plastic, usdzResourceName: nil),
        ItemType(name: "Emergency Exit",    sfSymbol: "door.right.hand.open",     category: .safety, combustionMaterial: .fireproof, usdzResourceName: nil),
        ItemType(name: "Sprinkler",         sfSymbol: "drop.fill",                category: .safety, combustionMaterial: .metal, usdzResourceName: nil),
        ItemType(name: "Alarm",             sfSymbol: "bell.fill",                category: .safety, combustionMaterial: .metal, usdzResourceName: nil),

        // Equipment
        ItemType(name: "Monitor",  sfSymbol: "display",                     category: .equipment, combustionMaterial: .plastic, usdzResourceName: nil),
        ItemType(name: "Laptop",   sfSymbol: "laptopcomputer",              category: .equipment, combustionMaterial: .plastic, usdzResourceName: nil),
        ItemType(name: "Printer",  sfSymbol: "printer.fill",                category: .equipment, combustionMaterial: .plastic, usdzResourceName: nil),
        ItemType(name: "Phone",    sfSymbol: "phone.fill",                  category: .equipment, combustionMaterial: .plastic, usdzResourceName: nil),
        ItemType(name: "Projector", sfSymbol: "video.fill",                 category: .equipment, combustionMaterial: .plastic, usdzResourceName: nil),
        ItemType(name: "Server",   sfSymbol: "externaldrive.fill",          category: .equipment, combustionMaterial: .metal, usdzResourceName: nil),
    ]
}

struct PlacedItem: Identifiable {
    let id: UUID
    let itemType: ItemType
    var position: SIMD3<Float>
    /// The original user-placed fire that this marker grew from. For an ignition
    /// point, this is its own ID; non-fire items have no source.
    let fireSourceID: UUID?
}

struct PlacedItemComponent: Component {
    var itemID: UUID
}
