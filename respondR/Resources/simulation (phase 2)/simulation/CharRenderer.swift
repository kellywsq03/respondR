//
//  CharRenderer.swift
//  respondR
//
//  Created by Tristan Lyn on 8/8/26.
//
import RealityKit
import UIKit
import simd

/// Leaves a static, mesh-conforming char patch behind for completed burns.
/// Unlike FireRenderer (which recycles a small pool across active cells),
/// these marks are created only after a cell reaches `.burntOut`.
@MainActor
final class CharRenderer {
    private let root: Entity
    private let cellSize: Float
    private let surfacePatch: (SIMD3<Float>, Float) -> MeshScanner.SurfacePatch?
    private var marks: [Entity] = []

    init(
        root: Entity,
        cellSize: Float,
        surfacePatch: @escaping (SIMD3<Float>, Float) -> MeshScanner.SurfacePatch?
    ) {
        self.root = root
        self.cellSize = cellSize
        self.surfacePatch = surfacePatch
    }

    /// Call once per tick with FireSimulation.drainNewlyBurnt().
    func addCompletedBurns(_ positions: [SIMD3<Float>]) {
        guard !positions.isEmpty else { return }
        for position in positions {
            guard let patch = surfacePatch(position, cellSize * 0.8) else {
                continue
            }

            var descriptor = MeshDescriptor(name: "mesh-conforming-char")
            descriptor.positions = MeshBuffers.Positions(patch.positions)
            descriptor.normals = MeshBuffers.Normals(patch.normals)
            descriptor.primitives = .triangles(patch.indices)

            let faceCount = patch.indices.count / 3
            descriptor.materials = .perFace(
                (0..<faceCount).map { face in
                    if face.isMultiple(of: 7) { return 2 }
                    if face.isMultiple(of: 3) { return 1 }
                    return 0
                }
            )

            guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
                continue
            }

            let entity = ModelEntity(mesh: mesh, materials: Self.charMaterials)
            entity.name = "Completed burn char"
            root.addChild(entity)
            marks.append(entity)
        }
    }

    func clear() {
        for entity in marks { entity.removeFromParent() }
        marks.removeAll()
    }

    private static let charMaterials: [SimpleMaterial] = [
        SimpleMaterial(
            color: UIColor(red: 0.012, green: 0.010, blue: 0.008, alpha: 0.96),
            roughness: 1.0,
            isMetallic: false
        ),
        SimpleMaterial(
            color: UIColor(red: 0.035, green: 0.024, blue: 0.018, alpha: 0.93),
            roughness: 0.98,
            isMetallic: false
        ),
        SimpleMaterial(
            color: UIColor(red: 0.075, green: 0.068, blue: 0.058, alpha: 0.86),
            roughness: 1.0,
            isMetallic: false
        )
    ]
}
