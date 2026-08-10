import Foundation
import simd

/// A persisted scan of the training room: every occupied fire-grid cell center,
/// stored relative to one ARKit world anchor so the map can be re-aligned to the
/// real room in any later session. Scan once, train forever.
struct RoomMap: Codable {
    var anchorID: UUID
    var cellSize: Float
    /// Anchor-local cell-center coordinates, flattened as xyz triples.
    var packedCells: [Float]

    var cellCount: Int { packedCells.count / 3 }

    /// Packs world-space cell centers into the anchor's local space.
    init(anchorID: UUID, cellSize: Float, originFromAnchor: simd_float4x4, worldCells: [SIMD3<Float>]) {
        self.anchorID = anchorID
        self.cellSize = cellSize
        let anchorFromOrigin = originFromAnchor.inverse
        var packed = [Float]()
        packed.reserveCapacity(worldCells.count * 3)
        for cell in worldCells {
            let local = anchorFromOrigin * SIMD4<Float>(cell, 1)
            packed.append(local.x)
            packed.append(local.y)
            packed.append(local.z)
        }
        self.packedCells = packed
    }

    /// Unpacks the stored cells back into world space using the anchor's
    /// transform from the current session.
    func worldPositions(originFromAnchor: simd_float4x4) -> [SIMD3<Float>] {
        var world = [SIMD3<Float>]()
        world.reserveCapacity(cellCount)
        var index = 0
        while index + 2 < packedCells.count {
            let local = SIMD4<Float>(
                packedCells[index], packedCells[index + 1], packedCells[index + 2], 1)
            let position = originFromAnchor * local
            world.append(SIMD3<Float>(position.x, position.y, position.z))
            index += 3
        }
        return world
    }
}

/// Atomic on-disk persistence for the Phase 2 room map. Stateless.
enum RoomMapStore {
    static let filename = "phase2-room-map.plist"

    static var fileURL: URL {
        get throws {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
            let directory = support.appendingPathComponent("respondR", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(filename)
        }
    }

    static func load() -> RoomMap? {
        guard let url = try? fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(RoomMap.self, from: data)
    }

    static func save(_ map: RoomMap) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(map)
        try data.write(to: fileURL, options: [.atomic])
    }

    static func delete() {
        guard let url = try? fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
