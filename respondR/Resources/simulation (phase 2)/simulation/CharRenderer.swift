//
//  CharRenderer.swift
//  respondR
//
//  Created by Tristan Lyn on 8/8/26.
//
import RealityKit
import UIKit
import simd

/// Leaves a static charred mark behind at each cell that has burnt out.
/// Unlike FireRenderer (which recycles a small pool across *currently*
/// active cells), marks are permanent once placed — so this just grows
/// an entity per newly-burnt cell and never touches it again.
@MainActor
final class CharRenderer {
    private let root: Entity
    private let cellSize: Float
    private var marks: [Entity] = []

    init(root: Entity, cellSize: Float) {
        self.root = root
        self.cellSize = cellSize
    }

    /// Call once per tick with FireSimulation.drainNewlyBurnt().
    func add(_ positions: [SIMD3<Float>]) {
        guard !positions.isEmpty else { return }
        for p in positions {
            let entity = ModelEntity(
                mesh: .generatePlane(width: cellSize * 0.9, depth: cellSize * 0.9),
                materials: [UnlitMaterial(color: UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))]
            )
            entity.position = p
            root.addChild(entity)
            marks.append(entity)
        }
    }

    func clear() {
        for entity in marks { entity.removeFromParent() }
        marks.removeAll()
    }
}
