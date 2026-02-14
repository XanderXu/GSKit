import RealityKit

@available(macOS 26.0, *)
@MainActor
enum GSLowLevelMeshFactory {
    static func makeMesh(from data: GSMeshBuildResult) throws -> LowLevelMesh {
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: data.vertexCount,
            vertexAttributes: [
                .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
                .init(semantic: .uv0, format: .float2, layoutIndex: 0, offset: 12),
                .init(semantic: .color, format: .float4, layoutIndex: 0, offset: 20),
            ],
            vertexLayouts: [
                .init(bufferIndex: 0, bufferOffset: 0, bufferStride: 36),
            ],
            indexCapacity: data.indexCount,
            indexType: .uint32
        )

        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { destination in
            data.vertexData.withUnsafeBytes { source in
                guard let sourceBase = source.baseAddress,
                      let destinationBase = destination.baseAddress else {
                    return
                }
                destinationBase.copyMemory(
                    from: sourceBase,
                    byteCount: min(destination.count, source.count)
                )
            }
        }

        mesh.replaceUnsafeMutableIndices { destination in
            data.indexData.withUnsafeBytes { source in
                guard let sourceBase = source.baseAddress,
                      let destinationBase = destination.baseAddress else {
                    return
                }
                destinationBase.copyMemory(
                    from: sourceBase,
                    byteCount: min(destination.count, source.count)
                )
            }
        }

        mesh.parts.replaceAll(data.parts)
        return mesh
    }
}
