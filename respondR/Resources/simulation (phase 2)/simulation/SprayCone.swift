import Foundation
import simd

/// Platform-independent representation of the extinguisher's affected volume.
struct SprayCone {
    let apex: SIMD3<Float>
    let direction: SIMD3<Float>
    let maxDistance: Float
    let halfAngleRadians: Float

    init(
        apex: SIMD3<Float>,
        direction: SIMD3<Float>,
        maxDistance: Float,
        halfAngleRadians: Float
    ) {
        self.apex = apex
        self.direction = simd_length_squared(direction) > 0
            ? simd_normalize(direction)
            : SIMD3<Float>(0, 0, -1)
        self.maxDistance = max(0, maxDistance)
        self.halfAngleRadians = max(0, halfAngleRadians)
    }

    func contains(_ point: SIMD3<Float>, padding: Float = 0) -> Bool {
        let offset = point - apex
        let projection = simd_dot(offset, direction)
        guard projection >= 0, projection <= maxDistance else { return false }

        let radialDistance = simd_length(offset - direction * projection)
        let coneRadius = projection * tan(halfAngleRadians)
        return radialDistance <= coneRadius + max(0, padding)
    }
}
