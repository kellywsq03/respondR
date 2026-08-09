import Foundation
import RealityKit

struct FloorGrid {
    let cols: Int
    let rows: Int
    let cellSize: Float           // meters, ~0.025
    let originLocal: SIMD3<Float> // tabletop-local coord of cell (0,0) corner
    let floorY: Float             // detected floor Y in tabletop-local coords
    var walkable: [[Bool]]        // [row][col]
    var fireIntensity: [[Int]]    // [row][col], 0 = no fire (foundation for later phase)
    var occupiedBy: [[UUID?]]     // [row][col] — itemID of placed item, or nil if free

    func cellCenterLocal(col: Int, row: Int) -> SIMD3<Float> {
        SIMD3(
            originLocal.x + (Float(col) + 0.5) * cellSize,
            floorY,
            originLocal.z + (Float(row) + 0.5) * cellSize
        )
    }

    /// BFS outward from the target cell to find the closest walkable AND free (not
    /// occupied) cell. Returns cell indices, or nil if none exist. Used by tap-to-place
    /// to auto-snap when the exact tapped cell is blocked or already occupied.
    func nearestFreeWalkableCell(to local: SIMD3<Float>, maxRadius: Int = 20) -> (col: Int, row: Int)? {
        let startCol: Int
        let startRow: Int
        if let inside = cellAt(local: local) {
            startCol = inside.col
            startRow = inside.row
        } else {
            // Clamp to the nearest valid indices so BFS still starts on the grid.
            startCol = max(0, min(cols - 1, Int((local.x - originLocal.x) / cellSize)))
            startRow = max(0, min(rows - 1, Int((local.z - originLocal.z) / cellSize)))
        }
        if isWalkable(col: startCol, row: startRow) && isFree(col: startCol, row: startRow) {
            return (startCol, startRow)
        }
        var visited = Array(repeating: Array(repeating: false, count: cols), count: rows)
        var queue: [(col: Int, row: Int, dist: Int)] = [(startCol, startRow, 0)]
        visited[startRow][startCol] = true
        var head = 0
        while head < queue.count {
            let (c, r, d) = queue[head]; head += 1
            if d >= maxRadius { continue }
            for (dc, dr) in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)] {
                let nc = c + dc, nr = r + dr
                if nc < 0 || nc >= cols || nr < 0 || nr >= rows { continue }
                if visited[nr][nc] { continue }
                visited[nr][nc] = true
                if walkable[nr][nc] && occupiedBy[nr][nc] == nil {
                    return (nc, nr)
                }
                queue.append((nc, nr, d + 1))
            }
        }
        return nil
    }

    /// BFS outward from the target cell to find the closest walkable cell.
    /// Returns the world-local center of that cell, or nil if the grid has no walkable cells.
    func nearestWalkableCenter(to local: SIMD3<Float>) -> SIMD3<Float>? {
        guard let (startCol, startRow) = cellAt(local: local) else {
            // Outside grid — scan whole grid for any walkable + closest by Manhattan distance
            var best: (col: Int, row: Int, dist: Int)?
            let (targetCol, targetRow) = (
                Int((local.x - originLocal.x) / cellSize),
                Int((local.z - originLocal.z) / cellSize)
            )
            for r in 0..<rows {
                for c in 0..<cols where walkable[r][c] {
                    let d = abs(c - targetCol) + abs(r - targetRow)
                    if best == nil || d < best!.dist { best = (c, r, d) }
                }
            }
            return best.map { cellCenterLocal(col: $0.col, row: $0.row) }
        }
        if walkable[startRow][startCol] {
            return cellCenterLocal(col: startCol, row: startRow)
        }
        var visited = Array(repeating: Array(repeating: false, count: cols), count: rows)
        var queue: [(col: Int, row: Int)] = [(startCol, startRow)]
        visited[startRow][startCol] = true
        var head = 0
        while head < queue.count {
            let (c, r) = queue[head]; head += 1
            for (dc, dr) in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)] {
                let nc = c + dc, nr = r + dr
                if nc < 0 || nc >= cols || nr < 0 || nr >= rows { continue }
                if visited[nr][nc] { continue }
                visited[nr][nc] = true
                if walkable[nr][nc] {
                    return cellCenterLocal(col: nc, row: nr)
                }
                queue.append((nc, nr))
            }
        }
        return nil
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

    func isFree(col: Int, row: Int) -> Bool {
        guard col >= 0, col < cols, row >= 0, row < rows else { return false }
        return occupiedBy[row][col] == nil
    }

    func occupant(col: Int, row: Int) -> UUID? {
        guard col >= 0, col < cols, row >= 0, row < rows else { return nil }
        return occupiedBy[row][col]
    }

    mutating func occupy(col: Int, row: Int, itemID: UUID) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        occupiedBy[row][col] = itemID
    }

    mutating func free(col: Int, row: Int) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        occupiedBy[row][col] = nil
    }

    var walkableCount: Int {
        walkable.reduce(0) { $0 + $1.filter { $0 }.count }
    }
}
