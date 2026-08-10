import Foundation
import simd

enum CellState {
    case unburned, igniting, burning, burntOut
}

struct FireVisualSample {
    let position: SIMD3<Float>
    let scale: Float
}

/// Tick-based fire spread over a FireGrid. Pure logic — no RealityKit.
///
/// Bounded by design: at most `maxActive` cells are igniting/burning at once,
/// each burning cell ignites at most `spreadFanout` neighbors per `spreadInterval`
/// (a steady crawl, not an explosion), and burnt-out cells leave the active set
/// so per-tick work stays small.
final class FireSimulation {
    private var grid: FireGrid
    private let ignitionDuration: TimeInterval
    private let burnDuration: TimeInterval
    private let spreadInterval: TimeInterval
    private let maxActive: Int
    private let spreadFanout: Int

    private struct Runtime {
        var state: CellState  // only .igniting or .burning live here
        var phaseStart: TimeInterval
        var phaseEnd: TimeInterval
        var nextSpread: TimeInterval
    }
    /// Only igniting/burning cells live here — kept small (≤ maxActive).
    private var runtime: [SIMD3<Int32>: Runtime] = [:]
    /// Cells that have burnt out; never re-ignite.
    private var burnt: Set<SIMD3<Int32>> = []
    /// Cells manually extinguished; terminal like burnt cells, but never charred.
    private var extinguished: Set<SIMD3<Int32>> = []
    /// World positions of cells that burnt out since the last `drainNewlyBurnt()` call.
    private var pendingBurnt: [SIMD3<Float>] = []

    init(
        cellSize: Float,
        ignitionDuration: TimeInterval = 0.6,
        burnDuration: TimeInterval = 20.0,
        spreadInterval: TimeInterval = 20,
        maxActive: Int = 50,
        spreadFanout: Int = 1
    ) {
        self.grid = FireGrid(cellSize: cellSize)
        self.ignitionDuration = ignitionDuration
        self.burnDuration = burnDuration
        self.spreadInterval = spreadInterval
        self.maxActive = maxActive
        self.spreadFanout = spreadFanout
    }

    var cellCount: Int { grid.count }
    var activeCount: Int { runtime.count }
    var gridCellSize: Float { grid.cellSize }
    /// World-space centers of every occupied cell (for persisting a room map).
    var occupiedCellCenters: [SIMD3<Float>] { grid.centers }

    func insertGeometry(_ positions: [SIMD3<Float>]) {
        grid.insert(positions)
    }

    @discardableResult
    func ignite(at p: SIMD3<Float>, now: TimeInterval) -> Bool {
        guard let c = grid.nearest(to: p) else { return false }
        return igniteCell(c, now: now)
    }

    /// Selects and ignites a complete, separated set of fires around the
    /// learner. No cells are changed unless the full requested set exists.
    /// The default ranges match the historical near-user behaviour; a restored
    /// room map lets callers widen `horizontalDistance` to the whole room.
    @discardableResult
    func igniteRandomFires(
        around headPosition: SIMD3<Float>,
        count: Int = 5,
        now: TimeInterval,
        horizontalDistance: ClosedRange<Float> = 1.5...4.0,
        verticalOffset: ClosedRange<Float> = -1.8 ... -0.35
    ) -> [SIMD3<Float>] {
        guard count > 0, runtime.count + count <= maxActive else { return [] }

        let candidates = grid.occupiedCells(
            around: headPosition,
            horizontalDistance: horizontalDistance,
            verticalOffset: verticalOffset
        ).filter { coordinate in
            runtime[coordinate] == nil
                && !burnt.contains(coordinate)
                && !extinguished.contains(coordinate)
        }.shuffled()

        var selectedCoordinates: [SIMD3<Int32>] = []
        var selectedPositions: [SIMD3<Float>] = []
        selectedCoordinates.reserveCapacity(count)
        selectedPositions.reserveCapacity(count)

        for coordinate in candidates {
            let position = grid.center(of: coordinate)
            guard selectedPositions.allSatisfy({ simd_distance($0, position) >= 0.8 }) else {
                continue
            }

            selectedCoordinates.append(coordinate)
            selectedPositions.append(position)
            if selectedCoordinates.count == count { break }
        }

        guard selectedCoordinates.count == count else { return [] }

        var insertedCoordinates: [SIMD3<Int32>] = []
        for coordinate in selectedCoordinates {
            guard igniteCell(coordinate, now: now) else {
                for inserted in insertedCoordinates {
                    runtime[inserted] = nil
                }
                return []
            }
            insertedCoordinates.append(coordinate)
        }

        return selectedPositions
    }

    @discardableResult
    private func igniteCell(_ c: SIMD3<Int32>, now: TimeInterval) -> Bool {
        guard runtime[c] == nil,
              !burnt.contains(c),
              !extinguished.contains(c),
              runtime.count < maxActive
        else { return false }
        runtime[c] = Runtime(
            state: .igniting,
            phaseStart: now,
            phaseEnd: now + ignitionDuration,
            nextSpread: .infinity
        )
        return true
    }

    func tick(now: TimeInterval) {
        for coord in Array(runtime.keys) {
            guard var rt = runtime[coord] else { continue }

            switch rt.state {
            case .igniting:
                if now >= rt.phaseEnd {
                    rt.state = .burning
                    rt.phaseStart = now
                    rt.phaseEnd = now + burnDuration
                    rt.nextSpread = now + spreadInterval
                }
                runtime[coord] = rt

            case .burning:
                if now >= rt.nextSpread {
                    var lit = 0
                    for n in grid.neighbors(of: coord) {
                        if lit >= spreadFanout || runtime.count >= maxActive {
                            break
                        }
                        if igniteCell(n, now: now) { lit += 1 }
                    }
                    rt.nextSpread = now + spreadInterval
                }
                if now >= rt.phaseEnd {
                    rt.state = .burntOut
                }
                if rt.state == .burntOut {
                    runtime[coord] = nil
                    burnt.insert(coord)
                    pendingBurnt.append(grid.center(of: coord))
                } else {
                    runtime[coord] = rt
                }

            case .unburned, .burntOut:
                break
            }
        }
    }

    /// Stable visual samples for cells currently igniting or burning.
    func activeVisuals(now: TimeInterval) -> [FireVisualSample] {
        runtime.keys.sorted { lhs, rhs in
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.z < rhs.z
        }.compactMap { coordinate in
            guard let runtime = runtime[coordinate] else { return nil }
            let scale: Float
            switch runtime.state {
            case .igniting:
                scale = 1
            case .burning:
                let elapsed = max(0, now - runtime.phaseStart)
                let progress = min(1, Float(elapsed / burnDuration))
                scale = 1 + 3 * progress
            case .unburned, .burntOut:
                return nil
            }
            return FireVisualSample(position: grid.center(of: coordinate), scale: scale)
        }
    }

    /// Removes fires covered by extinguisher spray without marking them burnt out.
    @discardableResult
    func extinguish(in cone: SprayCone) -> [SIMD3<Float>] {
        var removed: [SIMD3<Float>] = []
        for coord in Array(runtime.keys) {
            let position = grid.center(of: coord)
            if cone.contains(position, padding: grid.cellSize * 0.5) {
                runtime[coord] = nil
                extinguished.insert(coord)
                removed.append(position)
            }
        }
        return removed
    }

    /// World positions of cells that have burnt out since the last call.
    /// Call once per tick and hand the result to a renderer.
    func drainNewlyBurnt() -> [SIMD3<Float>] {
        defer { pendingBurnt.removeAll() }
        return pendingBurnt
    }

    func reset() {
        runtime.removeAll()
        burnt.removeAll()
        extinguished.removeAll()
        pendingBurnt.removeAll()
    }
}
