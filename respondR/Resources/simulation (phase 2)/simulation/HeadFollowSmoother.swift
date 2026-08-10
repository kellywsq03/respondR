import Foundation
import RealityKit
import simd

/// Stabilizes head-relative presentation without tying it to the fire tick rate.
///
/// Robustness matters here: the smoother re-blends its own output every frame,
/// so a single degenerate quaternion (denormalized by drift, or a slerp edge
/// case producing NaN) would poison every later frame and freeze the HUD in
/// place permanently. Each update therefore hemisphere-corrects, renormalizes,
/// and snaps back to the live head pose if anything non-finite appears.
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

        // Slerp the short way: quaternions double-cover rotations, and blending
        // into the opposite hemisphere swings the HUD the long way around.
        var targetRotation = targetTransform.rotation
        if simd_dot(currentTransform.rotation.vector, targetRotation.vector) < 0 {
            targetRotation = simd_quatf(vector: -targetRotation.vector)
        }

        currentTransform.translation = simd_mix(
            currentTransform.translation,
            targetTransform.translation,
            SIMD3<Float>(repeating: alpha)
        )
        currentTransform.rotation = simd_normalize(
            simd_slerp(currentTransform.rotation, targetRotation, alpha)
        )
        currentTransform.scale = targetTransform.scale

        // Degeneracy guard: never store or return a non-finite transform.
        if !Self.isFinite(currentTransform) {
            currentTransform = targetTransform
        }

        self.currentTransform = currentTransform
        return currentTransform.matrix
    }

    mutating func reset() {
        currentTransform = nil
    }

    private static func isFinite(_ transform: Transform) -> Bool {
        let t = transform.translation
        let r = transform.rotation.vector
        return t.x.isFinite && t.y.isFinite && t.z.isFinite
            && r.x.isFinite && r.y.isFinite && r.z.isFinite && r.w.isFinite
    }
}
