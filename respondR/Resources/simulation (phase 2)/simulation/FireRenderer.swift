import RealityKit
import simd

/// Shows flames at active fire-cell positions using a fixed pool of emitter
/// entities. Capacity caps concurrent emitters — the key on-device perf lever.
/// v1 rule: the first `capacity` active cells get flames.
@MainActor
final class FireRenderer {
    private let capacity: Int
    private var pool: [Entity] = []

    init(root: Entity, capacity: Int = 50) {
        self.capacity = capacity
        for _ in 0..<capacity {
            let e = Entity()
            e.components.set(FireParticles.makeFlame())
            e.isEnabled = false
            root.addChild(e)
            pool.append(e)
        }
    }

    func sync(active visuals: [FireVisualSample]) {
        for (i, entity) in pool.enumerated() {
            if i < visuals.count {
                let visual = visuals[i]
                entity.position = visual.position
                entity.scale = SIMD3<Float>(repeating: visual.scale)
                entity.isEnabled = true
            } else {
                entity.isEnabled = false
                entity.scale = SIMD3<Float>(repeating: 1)
            }
        }
    }

    func clear() {
        for entity in pool {
            entity.isEnabled = false
            entity.scale = SIMD3<Float>(repeating: 1)
        }
    }
}
