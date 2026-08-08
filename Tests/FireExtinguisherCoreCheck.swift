import Foundation
import simd

@main
enum FireExtinguisherCoreCheck {
    static func main() {
        let cone = SprayCone(
            apex: .zero,
            direction: SIMD3<Float>(0, 0, -4),
            maxDistance: 2,
            halfAngleRadians: 17.5 * .pi / 180
        )

        require(cone.contains(SIMD3<Float>(0, 0, -1)), "axis point must be inside")
        require(cone.contains(SIMD3<Float>(0.25, 0, -1)), "near-edge point must be inside")
        require(!cone.contains(SIMD3<Float>(0.5, 0, -1)), "wide point must be outside")
        require(!cone.contains(SIMD3<Float>(0, 0, 0.1)), "point behind apex must be outside")
        require(!cone.contains(SIMD3<Float>(0, 0, -2.1)), "point beyond reach must be outside")
        require(
            cone.contains(SIMD3<Float>(0.38, 0, -1), padding: 0.1),
            "cell padding must expand coverage"
        )

        require(
            ExtinguisherSizing.uniformScale(currentHeight: 2, targetHeight: 0.55) == 0.275,
            "two-metre asset must scale to 0.55 metres"
        )
        require(
            ExtinguisherSizing.uniformScale(currentHeight: 0, targetHeight: 0.55) == nil,
            "zero-height bounds must be rejected"
        )

        runSimulationChecks()
        runSessionChecks()
        print("Fire extinguisher core checks passed")
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func runSimulationChecks() {
        let onAxis = SIMD3<Float>(0.15, 0.15, -0.45)
        let outside = SIMD3<Float>(0.75, 0.15, -0.45)
        let cone = SprayCone(
            apex: .zero,
            direction: SIMD3<Float>(0, 0, -1),
            maxDistance: 2,
            halfAngleRadians: 17.5 * .pi / 180
        )

        let manual = FireSimulation(cellSize: 0.30, spreadInterval: 100)
        manual.insertGeometry([onAxis, outside])
        require(manual.ignite(at: onAxis, now: 0), "first fire must ignite")
        require(manual.ignite(at: outside, now: 0), "second fire must ignite")
        require(
            manual.extinguish(in: cone).count == 1,
            "cone must remove only the covered fire"
        )
        require(manual.activeCount == 1, "uncovered fire must remain active")
        require(manual.drainNewlyBurnt().isEmpty, "manual removal must not queue char")

        let natural = FireSimulation(
            cellSize: 0.30,
            ignitionDuration: 0.1,
            burnDuration: 0.1,
            spreadInterval: 100
        )
        natural.insertGeometry([onAxis])
        require(natural.ignite(at: onAxis, now: 0), "natural fire must ignite")
        natural.tick(now: 0.11)
        natural.tick(now: 0.22)
        require(natural.activeCount == 0, "expired fire must leave the active set")
        require(natural.drainNewlyBurnt().count == 1, "natural burnout must queue char")
    }
    static func runSessionChecks() {
        var session = FireExtinguisherSession()
        require(session.phase == .waitingToSpawn, "session must start waiting")
        require(!session.beginSpray(), "spray before pickup must be rejected")

        session.didSpawn()
        require(session.phase == .available, "spawn must make extinguisher available")
        require(!session.beginSpray(), "available extinguisher must not spray before pickup")
        require(session.pickUp(), "available extinguisher must be pickable")
        require(session.phase == .equipped, "pickup must permanently equip")

        require(session.beginSpray(), "held pinch must start spray")
        require(session.isSpraying, "spray state must remain active while held")
        session.endSpray()
        require(
            session.phase == .equipped && !session.isSpraying,
            "release must stop spray but keep equipment"
        )

        session.reset()
        require(
            session.phase == .waitingToSpawn && !session.isSpraying,
            "reset must clear equipment and spray"
        )
    }
}
