import RealityKit
import simd

/// Shows flames at active fire-cell positions using a fixed pool of emitter
/// entities. Capacity caps concurrent emitters — the key on-device perf lever.
/// v1 rule: the first `capacity` active cells get flames.
@MainActor
final class FireRenderer {
    private let capacity: Int
    private var pool: [Entity] = []

    init(root: Entity, capacity: Int = 24) {
        self.capacity = capacity
        for _ in 0..<capacity {
            let e = Entity()
            e.components.set(FireParticles.makeFlame())
            e.isEnabled = false
            root.addChild(e)
            pool.append(e)
        }
    }

    func sync(active positions: [SIMD3<Float>]) {
        for (i, entity) in pool.enumerated() {
            if i < positions.count {
                entity.position = positions[i]
                entity.isEnabled = true
            } else {
                entity.isEnabled = false
            }
        }
    }

    func clear() {
        for entity in pool { entity.isEnabled = false }
    }
}
