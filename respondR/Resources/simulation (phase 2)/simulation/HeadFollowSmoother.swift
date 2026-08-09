import Foundation
import RealityKit
import simd

/// Stabilizes head-relative presentation without tying it to the fire tick rate.
struct HeadFollowSmoother {
    private static let responseWindow: TimeInterval = 0.12
    private var currentTransform: Transform?

    mutating func update(
        target: simd_float4x4,
        deltaTime: TimeInterval
    ) -> simd_float4x4 {
        let targetTransform = Transform(matrix: target)
        guard var currentTransform else {
            self.currentTransform = targetTransform
            return target
        }

        let elapsed = max(0, deltaTime)
        let alpha = Float(1 - exp(-elapsed / Self.responseWindow))
        currentTransform.translation = simd_mix(
            currentTransform.translation,
            targetTransform.translation,
            SIMD3<Float>(repeating: alpha)
        )
        currentTransform.rotation = simd_slerp(
            currentTransform.rotation,
            targetTransform.rotation,
            alpha
        )
        currentTransform.scale = targetTransform.scale
        self.currentTransform = currentTransform
        return currentTransform.matrix
    }

    mutating func reset() {
        currentTransform = nil
    }
}
