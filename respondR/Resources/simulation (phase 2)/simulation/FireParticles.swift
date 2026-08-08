import RealityKit
import UIKit

/// Builds a code-configured flame particle emitter (no Reality Composer Pro).
enum FireParticles {
    static func makeFlame() -> ParticleEmitterComponent {
        var e = ParticleEmitterComponent()
        e.emitterShape = .sphere
        e.emitterShapeSize = [0.05, 0.05, 0.05]
        e.birthDirection = .world
        e.emissionDirection = [0, 1, 0]     // rise upward (buoyancy)
        e.speed = 0.25

        // Flames: hot -> cool over life, additive so cores glow.
        // Kept modest on purpose — many emitters run at once, so per-emitter
        // birth rate dominates GPU cost.
        e.mainEmitter.birthRate = 90
        e.mainEmitter.lifeSpan = 0.6
        e.mainEmitter.size = 0.04
        e.mainEmitter.spreadingAngle = .pi / 10
        e.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1.0)),
            end:   .single(UIColor(red: 0.85, green: 0.12, blue: 0.0, alpha: 0.0)))
        e.mainEmitter.blendMode = .additive

        return e
    }
}
