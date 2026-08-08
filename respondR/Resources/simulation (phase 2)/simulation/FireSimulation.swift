import Foundation
import simd

enum CellState {
    case unburned, igniting, burning, burntOut
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
        var phaseEnd: TimeInterval
        var nextSpread: TimeInterval
    }
    /// Only igniting/burning cells live here — kept small (≤ maxActive).
    private var runtime: [SIMD3<Int32>: Runtime] = [:]
    /// Cells that have burnt out; never re-ignite.
    private var burnt: Set<SIMD3<Int32>> = []
    /// World positions of cells that burnt out since the last `drainNewlyBurnt()` call.
    private var pendingBurnt: [SIMD3<Float>] = []

    init(
        cellSize: Float,
        ignitionDuration: TimeInterval = 0.6,
        burnDuration: TimeInterval = 10.0,
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

    func insertGeometry(_ positions: [SIMD3<Float>]) {
        grid.insert(positions)
    }

    @discardableResult
    func ignite(at p: SIMD3<Float>, now: TimeInterval) -> Bool {
        guard let c = grid.nearest(to: p) else { return false }
        return igniteCell(c, now: now)
    }

    @discardableResult
    private func igniteCell(_ c: SIMD3<Int32>, now: TimeInterval) -> Bool {
        guard runtime[c] == nil, !burnt.contains(c), runtime.count < maxActive
        else { return false }
        runtime[c] = Runtime(
            state: .igniting,
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

    /// World positions of cells currently igniting or burning.
    func activePositions() -> [SIMD3<Float>] {
        runtime.keys.map { grid.center(of: $0) }
    }

    /// Removes fires covered by extinguisher spray without marking them burnt out.
    @discardableResult
    func extinguish(in cone: SprayCone) -> [SIMD3<Float>] {
        var removed: [SIMD3<Float>] = []
        for coord in Array(runtime.keys) {
            let position = grid.center(of: coord)
            if cone.contains(position, padding: grid.cellSize * 0.5) {
                runtime[coord] = nil
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
        pendingBurnt.removeAll()
    }
}
