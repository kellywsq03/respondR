import ARKit
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

/// Owns all ARKit scene-reconstruction work: runs the provider, turns each
/// `MeshAnchor` into a wireframe `ModelEntity`, and keeps them in sync as the
/// user moves around the room.
///
/// The wireframe is built as real line geometry (`LowLevelMesh`, `.line`
/// topology) with an unlit material, so it needs no Reality Composer Pro shader.
@MainActor
final class MeshScanner {
    private let session = ARKitSession()
    private let sceneReconstruction = SceneReconstructionProvider()
    private let worldTracking = WorldTrackingProvider()
    private let rootEntity: Entity
    private var worldTrackingRunning = false

    enum Mode { case wireframe, fire }
    var mode: Mode = .wireframe
    /// Called with new world-space vertex positions each anchor update (fire mode).
    var onGeometryUpdate: (([SIMD3<Float>]) -> Void)?

    private var meshEntities: [UUID: ModelEntity] = [:]
    private var exportGeometry: [UUID: RoomExporter.Mesh] = [:]
    private var meshVisible = true
    private var wireColor = UIColor(red: 0.75, green: 1.0, blue: 0.15, alpha: 1.0)

    init(rootEntity: Entity) {
        self.rootEntity = rootEntity
    }

    /// Starts the ARKit session and consumes anchor updates until `stop()`.
    func start() async {
        print("MeshDebug: MeshScanner.start; isSupported=\(SceneReconstructionProvider.isSupported)")
        guard SceneReconstructionProvider.isSupported else { return }
        do {
            var providers: [any DataProvider] = [sceneReconstruction]
            if WorldTrackingProvider.isSupported {
                providers.append(worldTracking)
                worldTrackingRunning = true
            }
            try await session.run(providers)
            print("MeshDebug: ARKit session.run succeeded")
        } catch {
            worldTrackingRunning = false
            print("MeshScanner: failed to start session: \(error)")
            return
        }

        for await update in sceneReconstruction.anchorUpdates {
            let anchor = update.anchor
            switch update.event {
            case .added, .updated:
                upsert(anchor)
            case .removed:
                meshEntities[anchor.id]?.removeFromParent()
                meshEntities[anchor.id] = nil
                exportGeometry[anchor.id] = nil
            }
        }
    }

    func stop() {
        session.stop()
        worldTrackingRunning = false
        for entity in meshEntities.values { entity.removeFromParent() }
        meshEntities.removeAll()
        exportGeometry.removeAll()
    }

    func setMeshVisible(_ visible: Bool) {
        meshVisible = visible
        for entity in meshEntities.values { entity.isEnabled = visible }
    }

    func updateColor(_ color: Color) {
        wireColor = UIColor(color)
        let mat = makeMaterial()
        for entity in meshEntities.values {
            entity.model?.materials = [mat]
        }
    }

    /// Returns the tracked device pose in the same world coordinate space as
    /// the reconstructed mesh and fire-cell positions.
    func queryHeadTransform() -> simd_float4x4? {
        guard worldTrackingRunning,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else {
            return nil
        }
        return anchor.originFromAnchorTransform
    }

    // MARK: - Internals

    private func makeMaterial() -> UnlitMaterial {
        UnlitMaterial(color: wireColor)
    }

    private func upsert(_ anchor: MeshAnchor) {
        guard let geo = extractGeometry(from: anchor) else { return }
        let world = worldMesh(from: geo, transform: anchor.originFromAnchorTransform)
        exportGeometry[anchor.id] = world

        switch mode {
        case .fire:
            onGeometryUpdate?(world.positions)
            guard let solid = solidMesh(from: geo) else { return }
            if let existing = meshEntities[anchor.id] {
                // Update visual/transform only. Collision is NOT regenerated per
                // update — that was a severe per-frame main-thread cost. The
                // once-generated collision stays close enough for tap ignition.
                existing.model = ModelComponent(mesh: solid, materials: [OcclusionMaterial()])
                existing.transform = Transform(matrix: anchor.originFromAnchorTransform)
            } else {
                let entity = ModelEntity(mesh: solid, materials: [OcclusionMaterial()])
                entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
                entity.generateCollisionShapes(recursive: false)
                entity.components.set(InputTargetComponent())
                rootEntity.addChild(entity)
                meshEntities[anchor.id] = entity
            }

        case .wireframe:
            guard let mesh = wireframeMesh(from: geo) else { return }
            if let existing = meshEntities[anchor.id] {
                existing.model = ModelComponent(mesh: mesh, materials: [makeMaterial()])
                existing.transform = Transform(matrix: anchor.originFromAnchorTransform)
            } else {
                let entity = ModelEntity(mesh: mesh, materials: [makeMaterial()])
                entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
                entity.isEnabled = meshVisible
                rootEntity.addChild(entity)
                meshEntities[anchor.id] = entity
            }
        }
    }

    /// Builds a solid triangle mesh (for the invisible occluder in fire mode).
    private func solidMesh(from geo: TriangleGeometry) -> MeshResource? {
        var d = MeshDescriptor(name: "occluder")
        d.positions = MeshBuffers.Positions(geo.positions)
        d.primitives = .triangles(geo.indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Merges all retained anchor geometry into one world-space mesh and writes
    /// it to Documents as Room-<timestamp>.usdc. Returns a user-facing status.
    func exportRoom() -> String {
        let merged = RoomExporter.merge(Array(exportGeometry.values))
        guard !merged.positions.isEmpty else {
            return "Look around to scan surfaces first, then export."
        }

        let stamp = Self.timestampFormatter.string(from: Date())
        let name = "Room-\(stamp).usdc"
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        let url = documents.appendingPathComponent(name)

        do {
            try RoomExporter.export(merged, to: url)
            return "Saved \(name) to Files."
        } catch {
            return "Export failed: \(error.localizedDescription)"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    // MARK: - Geometry extraction

    private struct TriangleGeometry {
        var positions: [SIMD3<Float>] // object space, shared vertices
        var indices: [UInt32]         // triangle indices, 3 per triangle
    }

    /// Reads the anchor's vertices and triangle face indices once; shared by the
    /// wireframe build and the export bake.
    private func extractGeometry(from anchor: MeshAnchor) -> TriangleGeometry? {
        let geometry = anchor.geometry
        let verts = geometry.vertices
        let faces = geometry.faces
        let triangleCount = faces.count
        guard triangleCount > 0, verts.count > 0 else { return nil }

        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(verts.count)
        for i in 0..<verts.count {
            positions.append(
                verts.buffer.contents()
                    .advanced(by: verts.offset + verts.stride * i)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee)
        }

        var indices = [UInt32]()
        indices.reserveCapacity(triangleCount * 3)
        for i in 0..<(triangleCount * 3) {
            indices.append(
                faces.buffer.contents()
                    .advanced(by: faces.bytesPerIndex * i)
                    .assumingMemoryBound(to: UInt32.self).pointee)
        }
        return TriangleGeometry(positions: positions, indices: indices)
    }

    /// Bakes object-space geometry into world space for export.
    private func worldMesh(from geo: TriangleGeometry,
                           transform: simd_float4x4) -> RoomExporter.Mesh {
        var world = [SIMD3<Float>]()
        world.reserveCapacity(geo.positions.count)
        for p in geo.positions {
            let w = transform * SIMD4<Float>(p, 1)
            world.append(SIMD3<Float>(w.x, w.y, w.z))
        }
        return RoomExporter.Mesh(positions: world, indices: geo.indices)
    }

    /// Builds a line-topology mesh (each triangle's three edges) for display.
    private func wireframeMesh(from geo: TriangleGeometry) -> MeshResource? {
        let vertexCount = geo.positions.count
        guard vertexCount > 0, !geo.indices.isEmpty else { return nil }

        var lineIndices = [UInt32]()
        lineIndices.reserveCapacity(geo.indices.count * 2)
        var t = 0
        while t < geo.indices.count {
            let a = geo.indices[t], b = geo.indices[t + 1], c = geo.indices[t + 2]
            lineIndices.append(a); lineIndices.append(b)
            lineIndices.append(b); lineIndices.append(c)
            lineIndices.append(c); lineIndices.append(a)
            t += 3
        }

        var minB = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxB = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in geo.positions { minB = simd.min(minB, p); maxB = simd.max(maxB, p) }

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = vertexCount
        descriptor.indexCapacity = lineIndices.count
        descriptor.vertexAttributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3, layoutIndex: 0, offset: 0)
        ]
        descriptor.vertexLayouts = [
            LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)
        ]
        descriptor.indexType = .uint32

        guard let lowLevel = try? LowLevelMesh(descriptor: descriptor) else { return nil }

        lowLevel.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let ptr = raw.bindMemory(to: SIMD3<Float>.self)
            for i in 0..<vertexCount { ptr[i] = geo.positions[i] }
        }
        lowLevel.withUnsafeMutableIndices { raw in
            let ptr = raw.bindMemory(to: UInt32.self)
            for i in 0..<lineIndices.count { ptr[i] = lineIndices[i] }
        }
        lowLevel.parts.replaceAll([
            LowLevelMesh.Part(indexCount: lineIndices.count, topology: .line,
                              bounds: BoundingBox(min: minB, max: maxB))
        ])
        return try? MeshResource(from: lowLevel)
    }
}
