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
    struct SurfacePatch {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var indices: [UInt32]
    }

    private struct SurfaceTriangle {
        let id: Int
        let a: SIMD3<Float>
        let b: SIMD3<Float>
        let c: SIMD3<Float>
        let normal: SIMD3<Float>

        var center: SIMD3<Float> { (a + b + c) / 3 }
    }

    private static let surfaceBucketSize: Float = 0.15

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
    private var surfaceBuckets: [UUID: [SIMD3<Int32>: [SurfaceTriangle]]] = [:]
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
                surfaceBuckets[anchor.id] = nil
            }
        }
    }

    func stop() {
        session.stop()
        worldTrackingRunning = false
        for entity in meshEntities.values { entity.removeFromParent() }
        meshEntities.removeAll()
        exportGeometry.removeAll()
        surfaceBuckets.removeAll()
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

    /// Selects an approximately horizontal scanned-surface point around the
    /// learner. Triangle IDs are de-duplicated per mesh anchor because one
    /// triangle can be retained in several spatial buckets.
    func randomFloorPosition(
        around headPosition: SIMD3<Float>,
        horizontalDistance: ClosedRange<Float>,
        verticalOffset: ClosedRange<Float>
    ) -> SIMD3<Float>? {
        var eligible: [SIMD3<Float>] = []
        let radius = horizontalDistance.upperBound
        let minimum = Self.bucketCoordinate(
            for: headPosition + SIMD3<Float>(-radius, verticalOffset.lowerBound, -radius)
        )
        let maximum = Self.bucketCoordinate(
            for: headPosition + SIMD3<Float>(radius, verticalOffset.upperBound, radius)
        )

        for buckets in surfaceBuckets.values {
            var seen: Set<Int> = []
            for x in minimum.x...maximum.x {
                for y in minimum.y...maximum.y {
                    for z in minimum.z...maximum.z {
                        let key = SIMD3<Int32>(x, y, z)
                        for triangle in buckets[key] ?? []
                        where seen.insert(triangle.id).inserted {
                            guard abs(triangle.normal.y) >= 0.75 else { continue }
                            let delta = triangle.center - headPosition
                            let distance = simd_length(SIMD2<Float>(delta.x, delta.z))
                            guard horizontalDistance.contains(distance),
                                  verticalOffset.contains(delta.y) else {
                                continue
                            }
                            eligible.append(triangle.center)
                        }
                    }
                }
            }
        }

        return eligible.shuffled().first.map { $0 + SIMD3<Float>(0, 0.01, 0) }
    }

    /// Returns an irregular renderable fragment of the reconstructed surface
    /// around a completed burn cell. The returned geometry is in world space
    /// and sits just above the occlusion mesh to prevent z-fighting.
    func makeCharPatch(near position: SIMD3<Float>, radius: Float) -> SurfacePatch? {
        let searchRadius = max(radius * 2.5, Self.surfaceBucketSize * 2)
        let candidates = surfaceTriangles(near: position, radius: searchRadius)
        guard !candidates.isEmpty else { return nil }

        var nearestTriangle: SurfaceTriangle?
        var nearestPoint = position
        var nearestDistanceSquared = Float.greatestFiniteMagnitude
        for triangle in candidates {
            let point = Self.closestPoint(position, on: triangle)
            let distanceSquared = simd_distance_squared(position, point)
            if distanceSquared < nearestDistanceSquared {
                nearestDistanceSquared = distanceSquared
                nearestTriangle = triangle
                nearestPoint = point
            }
        }

        guard let nearestTriangle,
              nearestDistanceSquared <= pow(max(radius * 1.8, 0.20), 2) else {
            return nil
        }

        var patchNormal = nearestTriangle.normal
        if let headTransform = queryHeadTransform() {
            let headPosition = SIMD3<Float>(
                headTransform.columns.3.x,
                headTransform.columns.3.y,
                headTransform.columns.3.z
            )
            if simd_dot(patchNormal, headPosition - nearestPoint) < 0 {
                patchNormal = -patchNormal
            }
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(candidates.count * 3)
        normals.reserveCapacity(candidates.count * 3)
        indices.reserveCapacity(candidates.count * 3)

        for triangle in candidates {
            let alignment = abs(simd_dot(triangle.normal, patchNormal))
            guard alignment >= 0.58 else { continue }

            let closest = Self.closestPoint(nearestPoint, on: triangle)
            let delta = closest - nearestPoint
            let normalDistance = abs(simd_dot(delta, patchNormal))
            let tangentDelta = delta - patchNormal * simd_dot(delta, patchNormal)
            let tangentDistance = simd_length(tangentDelta)
            let edgeNoise = Self.patchNoise(at: triangle.center, seed: position)
            let irregularRadius = radius * (0.76 + edgeNoise * 0.38)

            guard normalDistance <= max(0.025, radius * 0.28),
                  tangentDistance <= irregularRadius else {
                continue
            }

            var normal = triangle.normal
            if simd_dot(normal, patchNormal) < 0 { normal = -normal }
            let lift = 0.002 + edgeNoise * 0.0015
            let baseIndex = UInt32(positions.count)
            positions.append(triangle.a + normal * lift)
            positions.append(triangle.b + normal * lift)
            positions.append(triangle.c + normal * lift)
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [baseIndex, baseIndex + 1, baseIndex + 2])
        }

        guard !indices.isEmpty else { return nil }
        return SurfacePatch(positions: positions, normals: normals, indices: indices)
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
            indexSurface(world, for: anchor.id)
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

    private func indexSurface(_ mesh: RoomExporter.Mesh, for anchorID: UUID) {
        var buckets: [SIMD3<Int32>: [SurfaceTriangle]] = [:]
        var triangleID = 0
        var index = 0

        while index + 2 < mesh.indices.count {
            let ia = Int(mesh.indices[index])
            let ib = Int(mesh.indices[index + 1])
            let ic = Int(mesh.indices[index + 2])
            index += 3
            guard ia < mesh.positions.count,
                  ib < mesh.positions.count,
                  ic < mesh.positions.count else {
                continue
            }

            let a = mesh.positions[ia]
            let b = mesh.positions[ib]
            let c = mesh.positions[ic]
            let cross = simd_cross(b - a, c - a)
            let length = simd_length(cross)
            guard length > 0.00001 else { continue }

            let triangle = SurfaceTriangle(
                id: triangleID,
                a: a,
                b: b,
                c: c,
                normal: cross / length
            )
            triangleID += 1

            let minimum = Self.bucketCoordinate(for: simd.min(a, simd.min(b, c)))
            let maximum = Self.bucketCoordinate(for: simd.max(a, simd.max(b, c)))
            for x in minimum.x...maximum.x {
                for y in minimum.y...maximum.y {
                    for z in minimum.z...maximum.z {
                        buckets[SIMD3<Int32>(x, y, z), default: []].append(triangle)
                    }
                }
            }
        }

        surfaceBuckets[anchorID] = buckets
    }

    private func surfaceTriangles(
        near position: SIMD3<Float>,
        radius: Float
    ) -> [SurfaceTriangle] {
        let minimum = Self.bucketCoordinate(for: position - SIMD3<Float>(repeating: radius))
        let maximum = Self.bucketCoordinate(for: position + SIMD3<Float>(repeating: radius))
        var result: [SurfaceTriangle] = []

        for buckets in surfaceBuckets.values {
            var seen: Set<Int> = []
            for x in minimum.x...maximum.x {
                for y in minimum.y...maximum.y {
                    for z in minimum.z...maximum.z {
                        let key = SIMD3<Int32>(x, y, z)
                        for triangle in buckets[key] ?? [] where seen.insert(triangle.id).inserted {
                            result.append(triangle)
                        }
                    }
                }
            }
        }
        return result
    }

    private static func bucketCoordinate(for position: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3<Int32>(
            Int32(floor(position.x / surfaceBucketSize)),
            Int32(floor(position.y / surfaceBucketSize)),
            Int32(floor(position.z / surfaceBucketSize))
        )
    }

    private static func closestPoint(
        _ point: SIMD3<Float>,
        on triangle: SurfaceTriangle
    ) -> SIMD3<Float> {
        let ab = triangle.b - triangle.a
        let ac = triangle.c - triangle.a
        let ap = point - triangle.a
        let d1 = simd_dot(ab, ap)
        let d2 = simd_dot(ac, ap)
        if d1 <= 0, d2 <= 0 { return triangle.a }

        let bp = point - triangle.b
        let d3 = simd_dot(ab, bp)
        let d4 = simd_dot(ac, bp)
        if d3 >= 0, d4 <= d3 { return triangle.b }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 {
            let v = d1 / (d1 - d3)
            return triangle.a + v * ab
        }

        let cp = point - triangle.c
        let d5 = simd_dot(ab, cp)
        let d6 = simd_dot(ac, cp)
        if d6 >= 0, d5 <= d6 { return triangle.c }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 {
            let w = d2 / (d2 - d6)
            return triangle.a + w * ac
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0, d4 - d3 >= 0, d5 - d6 >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return triangle.b + w * (triangle.c - triangle.b)
        }

        let denominator = 1 / (va + vb + vc)
        let v = vb * denominator
        let w = vc * denominator
        return triangle.a + ab * v + ac * w
    }

    private static func patchNoise(
        at position: SIMD3<Float>,
        seed: SIMD3<Float>
    ) -> Float {
        var value = UInt32(bitPattern: Int32((position.x * 1000).rounded()))
        value ^= UInt32(bitPattern: Int32((position.y * 1000).rounded())) &* 1_668_525
        value ^= UInt32(bitPattern: Int32((position.z * 1000).rounded())) &* 1_013_904_223
        value ^= UInt32(bitPattern: Int32((seed.x * 100).rounded())) &* 374_761_393
        value ^= UInt32(bitPattern: Int32((seed.y * 100).rounded())) &* 668_265_263
        value ^= UInt32(bitPattern: Int32((seed.z * 100).rounded())) &* 2_246_822_519
        value ^= value >> 13
        value &*= 1_274_126_177
        value ^= value >> 16
        return Float(value & 0xFFFF) / Float(0xFFFF)
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
