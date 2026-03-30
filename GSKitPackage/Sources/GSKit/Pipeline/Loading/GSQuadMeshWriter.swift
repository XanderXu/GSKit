import Foundation
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

enum GSQuadMeshWriter {
    static func encode(
        splats: [GSSplatData],
        quadUV: [SIMD2<Float>]
    ) throws -> GSQuadMeshBuffers {
        let vertexCount = splats.count * 4
        let indexCount = splats.count * 6
        let vertexByteCount = vertexCount * MemoryLayout<GSMeshVertex>.stride
        let indexByteCount = indexCount * MemoryLayout<UInt32>.stride

        let vertexStorage = UnsafeMutableRawPointer.allocate(
            byteCount: vertexByteCount,
            alignment: MemoryLayout<GSMeshVertex>.alignment
        )
        let indexStorage = UnsafeMutableRawPointer.allocate(
            byteCount: indexByteCount,
            alignment: MemoryLayout<UInt32>.alignment
        )

        var adoptedVertexStorage = false
        var adoptedIndexStorage = false
        defer {
            if !adoptedVertexStorage { vertexStorage.deallocate() }
            if !adoptedIndexStorage { indexStorage.deallocate() }
        }

        let vertexPointer = vertexStorage.bindMemory(to: GSMeshVertex.self, capacity: vertexCount)
        let indexPointer = indexStorage.bindMemory(to: UInt32.self, capacity: indexCount)

        var minBounds = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for (index, splat) in splats.enumerated() {
            let baseVertexIndex = index * 4
            let baseIndexIndex = index * 6
            let premultipliedRGB = splat.rgb * splat.alpha

            for corner in 0..<4 {
                let uv = quadUV[corner]
                let position = splat.position + (splat.axisU * uv.x) + (splat.axisV * uv.y)
                minBounds = simd_min(minBounds, position)
                maxBounds = simd_max(maxBounds, position)

                vertexPointer[baseVertexIndex + corner] = GSMeshVertex(
                    px: position.x,
                    py: position.y,
                    pz: position.z,
                    u: uv.x,
                    v: uv.y,
                    r: premultipliedRGB.x,
                    g: premultipliedRGB.y,
                    b: premultipliedRGB.z,
                    a: splat.alpha
                )
            }

            let v0 = UInt32(baseVertexIndex + 0)
            let v1 = UInt32(baseVertexIndex + 1)
            let v2 = UInt32(baseVertexIndex + 2)
            let v3 = UInt32(baseVertexIndex + 3)
            indexPointer[baseIndexIndex + 0] = v0
            indexPointer[baseIndexIndex + 1] = v1
            indexPointer[baseIndexIndex + 2] = v2
            indexPointer[baseIndexIndex + 3] = v0
            indexPointer[baseIndexIndex + 4] = v2
            indexPointer[baseIndexIndex + 5] = v3
        }

        let vertexData = Data(
            bytesNoCopy: vertexStorage,
            count: vertexByteCount,
            deallocator: .custom { pointer, _ in pointer.deallocate() }
        )
        adoptedVertexStorage = true

        let indexData = Data(
            bytesNoCopy: indexStorage,
            count: indexByteCount,
            deallocator: .custom { pointer, _ in pointer.deallocate() }
        )
        adoptedIndexStorage = true

        let part = LowLevelMesh.Part(
            indexOffset: 0,
            indexCount: indexCount,
            topology: .triangle,
            materialIndex: 0,
            bounds: BoundingBox(min: minBounds, max: maxBounds)
        )

        return GSQuadMeshBuffers(
            vertexData: vertexData,
            indexData: indexData,
            parts: [part],
            vertexCount: vertexCount,
            indexCount: indexCount
        )
    }
}
