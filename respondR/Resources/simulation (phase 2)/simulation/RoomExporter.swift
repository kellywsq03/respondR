import Foundation
import ModelIO
import simd

/// Turns merged room geometry into a .usdc file via ModelIO. Stateless.
enum RoomExporter {
    struct Mesh {
        var positions: [SIMD3<Float>]
        var indices: [UInt32]
    }

    enum ExportError: LocalizedError {
        case unsupportedFormat
        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "USDC export isn't supported on this device."
            }
        }
    }

    /// Concatenates meshes into one, offsetting each mesh's indices by the
    /// running vertex count so triangles still point at the right vertices.
    static func merge(_ meshes: [Mesh]) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for m in meshes {
            let offset = UInt32(positions.count)
            positions.append(contentsOf: m.positions)
            indices.append(contentsOf: m.indices.map { $0 + offset })
        }
        return Mesh(positions: positions, indices: indices)
    }

    /// Writes the mesh to `url` as a binary USD (.usdc) file.
    static func export(_ mesh: Mesh, to url: URL) throws {
        guard MDLAsset.canExportFileExtension("usdc") else {
            throw ExportError.unsupportedFormat
        }

        let allocator = MDLMeshBufferDataAllocator()

        let positionData = mesh.positions.withUnsafeBytes { Data($0) }
        let vertexBuffer = allocator.newBuffer(with: positionData, type: .vertex)

        let indexData = mesh.indices.withUnsafeBytes { Data($0) }
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: mesh.indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil)

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0)
        // SIMD3<Float> is 16-byte aligned — stride MUST be 16, not 12.
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(
            stride: MemoryLayout<SIMD3<Float>>.stride)

        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: mesh.positions.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh])

        let asset = MDLAsset()
        asset.add(mdlMesh)
        try asset.export(to: url)
    }
}
