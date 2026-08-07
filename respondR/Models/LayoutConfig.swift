import RealityKit

struct WallSegment {
    var position: SIMD3<Float>
    var size: SIMD3<Float>
    var rotation: Float  // Y-axis rotation in radians
}

struct LayoutConfig: Identifiable {
    let id: Int
    let name: String
    let walls: [WallSegment]
    let floorSize: SIMD2<Float>
}

// Wall dimensions: 0.12 m tall (represents ~1.2 m at 1:10 scale — clearly visible at eye level)
// Wall center Y = 0.06 (= wallHeight / 2, sitting on the floor)
extension LayoutConfig {
    static let all: [LayoutConfig] = [layout1, layout2, layout3]

    // Layout 1: Simple rectangular room
    static let layout1 = LayoutConfig(
        id: 1,
        name: "Layout 1",
        walls: [
            WallSegment(position: [0,     0.06, -0.2],  size: [0.6,  0.12, 0.012], rotation: 0),
            WallSegment(position: [0,     0.06,  0.2],  size: [0.6,  0.12, 0.012], rotation: 0),
            WallSegment(position: [-0.3,  0.06,  0],    size: [0.4,  0.12, 0.012], rotation: .pi / 2),
            WallSegment(position: [ 0.3,  0.06,  0],    size: [0.4,  0.12, 0.012], rotation: .pi / 2),
        ],
        floorSize: SIMD2(0.6, 0.4)
    )

    // Layout 2: L-shaped room
    static let layout2 = LayoutConfig(
        id: 2,
        name: "Layout 2",
        walls: [
            WallSegment(position: [0,     0.06,  0.2],  size: [0.6,  0.12, 0.012], rotation: 0),
            WallSegment(position: [-0.15, 0.06, -0.2],  size: [0.3,  0.12, 0.012], rotation: 0),
            WallSegment(position: [0.15,  0.06,  0.0],  size: [0.3,  0.12, 0.012], rotation: 0),
            WallSegment(position: [-0.3,  0.06,  0],    size: [0.4,  0.12, 0.012], rotation: .pi / 2),
            WallSegment(position: [ 0.3,  0.06,  0.1],  size: [0.2,  0.12, 0.012], rotation: .pi / 2),
            WallSegment(position: [ 0.0,  0.06, -0.1],  size: [0.2,  0.12, 0.012], rotation: .pi / 2),
        ],
        floorSize: SIMD2(0.6, 0.4)
    )

    // Layout 3: Open-plan with a central corridor
    static let layout3 = LayoutConfig(
        id: 3,
        name: "Layout 3",
        walls: [
            WallSegment(position: [0,      0.06, -0.225], size: [0.7,  0.12, 0.012], rotation: 0),
            WallSegment(position: [0,      0.06,  0.225], size: [0.7,  0.12, 0.012], rotation: 0),
            WallSegment(position: [-0.35,  0.06,  0],     size: [0.45, 0.12, 0.012], rotation: .pi / 2),
            WallSegment(position: [ 0.35,  0.06,  0],     size: [0.45, 0.12, 0.012], rotation: .pi / 2),
            WallSegment(position: [-0.1,   0.06, -0.08],  size: [0.25, 0.12, 0.012], rotation: 0),
            WallSegment(position: [-0.1,   0.06,  0.08],  size: [0.25, 0.12, 0.012], rotation: 0),
            WallSegment(position: [ 0.15,  0.06, -0.08],  size: [0.2,  0.12, 0.012], rotation: 0),
            WallSegment(position: [ 0.15,  0.06,  0.08],  size: [0.2,  0.12, 0.012], rotation: 0),
        ],
        floorSize: SIMD2(0.7, 0.45)
    )
}
