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

// Wall dimensions: 0.30 m tall, 0.05 m thick — substantial 3D dollhouse walls
// Wall center Y = 0.15 (= wallHeight / 2, sitting on the floor)
extension LayoutConfig {
    static let all: [LayoutConfig] = [layout1, layout2, layout3]

    // Layout 1: Simple rectangular room — 0.8 m × 0.55 m floor, open-top box
    static let layout1 = LayoutConfig(
        id: 1,
        name: "Layout 1",
        walls: [
            WallSegment(position: [0,     0.15, -0.275], size: [0.8,  0.30, 0.05], rotation: 0),
            WallSegment(position: [0,     0.15,  0.275], size: [0.8,  0.30, 0.05], rotation: 0),
            WallSegment(position: [-0.4,  0.15,  0],     size: [0.55, 0.30, 0.05], rotation: .pi / 2),
            WallSegment(position: [ 0.4,  0.15,  0],     size: [0.55, 0.30, 0.05], rotation: .pi / 2),
        ],
        floorSize: SIMD2(0.8, 0.55)
    )

    // Layout 2: L-shaped room
    static let layout2 = LayoutConfig(
        id: 2,
        name: "Layout 2",
        walls: [
            WallSegment(position: [0,     0.15,  0.275], size: [0.8,  0.30, 0.05], rotation: 0),
            WallSegment(position: [-0.2,  0.15, -0.275], size: [0.4,  0.30, 0.05], rotation: 0),
            WallSegment(position: [ 0.2,  0.15,  0.0],   size: [0.4,  0.30, 0.05], rotation: 0),
            WallSegment(position: [-0.4,  0.15,  0],     size: [0.55, 0.30, 0.05], rotation: .pi / 2),
            WallSegment(position: [ 0.4,  0.15,  0.15],  size: [0.25, 0.30, 0.05], rotation: .pi / 2),
            WallSegment(position: [ 0.0,  0.15, -0.15],  size: [0.25, 0.30, 0.05], rotation: .pi / 2),
        ],
        floorSize: SIMD2(0.8, 0.55)
    )

    // Layout 3: Open-plan with a central corridor
    static let layout3 = LayoutConfig(
        id: 3,
        name: "Layout 3",
        walls: [
            WallSegment(position: [0,      0.15, -0.3],   size: [0.9,  0.30, 0.05], rotation: 0),
            WallSegment(position: [0,      0.15,  0.3],   size: [0.9,  0.30, 0.05], rotation: 0),
            WallSegment(position: [-0.45,  0.15,  0],     size: [0.6,  0.30, 0.05], rotation: .pi / 2),
            WallSegment(position: [ 0.45,  0.15,  0],     size: [0.6,  0.30, 0.05], rotation: .pi / 2),
            WallSegment(position: [-0.15,  0.15, -0.1],   size: [0.3,  0.30, 0.05], rotation: 0),
            WallSegment(position: [-0.15,  0.15,  0.1],   size: [0.3,  0.30, 0.05], rotation: 0),
            WallSegment(position: [ 0.2,   0.15, -0.1],   size: [0.25, 0.30, 0.05], rotation: 0),
            WallSegment(position: [ 0.2,   0.15,  0.1],   size: [0.25, 0.30, 0.05], rotation: 0),
        ],
        floorSize: SIMD2(0.9, 0.6)
    )
}
