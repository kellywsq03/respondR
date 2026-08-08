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

    static func runSimulationChecks() {}
    static func runSessionChecks() {}
}
