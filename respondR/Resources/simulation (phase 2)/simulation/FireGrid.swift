import Foundation
import simd

/// Voxelizes world-space surface points into a grid of fixed-size cells.
/// Pure geometry/topology — no RealityKit. Each occupied cell is a fire cell.
struct FireGrid {
    let cellSize: Float
    private(set) var occupied: Set<SIMD3<Int32>> = []

    init(cellSize: Float) {
        self.cellSize = cellSize
    }

    var count: Int { occupied.count }

    func coord(for p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3<Int32>(
            Int32(floor(p.x / cellSize)),
            Int32(floor(p.y / cellSize)),
            Int32(floor(p.z / cellSize)))
    }

    func center(of c: SIMD3<Int32>) -> SIMD3<Float> {
        (SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)) + 0.5) * cellSize
    }

    mutating func insert(_ positions: [SIMD3<Float>]) {
        for p in positions { occupied.insert(coord(for: p)) }
    }

    /// The occupied cells in the 26-cell neighborhood around `c`.
    func neighbors(of c: SIMD3<Int32>) -> [SIMD3<Int32>] {
        var result: [SIMD3<Int32>] = []
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    if dx == 0 && dy == 0 && dz == 0 { continue }
                    let n = SIMD3<Int32>(c.x + Int32(dx), c.y + Int32(dy), c.z + Int32(dz))
                    if occupied.contains(n) { result.append(n) }
                }
            }
        }
        return result
    }

    /// The occupied cell whose center is closest to `p` (nil if grid empty).
    func nearest(to p: SIMD3<Float>) -> SIMD3<Int32>? {
        var best: SIMD3<Int32>?
        var bestDist = Float.greatestFiniteMagnitude
        for c in occupied {
            let d = simd_distance_squared(center(of: c), p)
            if d < bestDist { bestDist = d; best = c }
        }
        return best
    }
}
