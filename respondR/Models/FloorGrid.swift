import Foundation
import RealityKit

struct FloorGrid {
    let cols: Int
    let rows: Int
    let cellSize: Float           // meters, ~0.025
    let originLocal: SIMD3<Float> // tabletop-local coord of cell (0,0) corner (floor Y)
    var walkable: [[Bool]]        // [row][col]
    var fireIntensity: [[Int]]    // [row][col], 0 = no fire (foundation for later phase)

    func cellCenterLocal(col: Int, row: Int) -> SIMD3<Float> {
        SIMD3(
            originLocal.x + (Float(col) + 0.5) * cellSize,
            originLocal.y,
            originLocal.z + (Float(row) + 0.5) * cellSize
        )
    }

    func cellAt(local: SIMD3<Float>) -> (col: Int, row: Int)? {
        let col = Int((local.x - originLocal.x) / cellSize)
        let row = Int((local.z - originLocal.z) / cellSize)
        guard col >= 0, col < cols, row >= 0, row < rows else { return nil }
        return (col, row)
    }

    func isWalkable(col: Int, row: Int) -> Bool {
        guard col >= 0, col < cols, row >= 0, row < rows else { return false }
        return walkable[row][col]
    }

    var walkableCount: Int {
        walkable.reduce(0) { $0 + $1.filter { $0 }.count }
    }
}
