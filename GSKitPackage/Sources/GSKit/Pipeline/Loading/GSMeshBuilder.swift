import Foundation
import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
enum GSMeshBuilder {
    static let device = MTLCreateSystemDefaultDevice()
    private static let maxRenderableSplats: Int = envInt("GSKIT_MAX_SPLATS", defaultValue: 0)

    static func buildStaticBakedMeshData(from ply: GSPLYFile) async throws -> GSMeshBuildResult {
        let props = ply.header.properties
        let xProp = try require(props, "x")
        let yProp = try require(props, "y")
        let zProp = try require(props, "z")

        let decodedSplats: [GSSplatData]
        let quadUV: [SIMD2<Float>]

        if props["scale_0"] != nil || props["rot_0"] != nil {
            decodedSplats = try await GSGaussianSplatDecoder.decode(
                from: ply,
                xProp: xProp,
                yProp: yProp,
                zProp: zProp
            )
            quadUV = [
                SIMD2<Float>(-2.5, -2.5),
                SIMD2<Float>(2.5, -2.5),
                SIMD2<Float>(2.5, 2.5),
                SIMD2<Float>(-2.5, 2.5),
            ]
        } else {
            decodedSplats = try await GSPointCloudDecoder.decode(
                from: ply,
                xProp: xProp,
                yProp: yProp,
                zProp: zProp
            )
            quadUV = [
                SIMD2<Float>(-3.0, -3.0),
                SIMD2<Float>(3.0, -3.0),
                SIMD2<Float>(3.0, 3.0),
                SIMD2<Float>(-3.0, 3.0),
            ]
        }

        guard !decodedSplats.isEmpty else {
            throw GSError.invalidPLYData("No valid splats found in .ply file.")
        }

        let splats = downsampleSplatsIfNeeded(decodedSplats)
        let meshBuffers = try GSQuadMeshWriter.encode(
            splats: splats,
            quadUV: quadUV
        )

        return GSMeshBuildResult(
            vertexData: meshBuffers.vertexData,
            indexData: meshBuffers.indexData,
            parts: meshBuffers.parts,
            vertexCount: meshBuffers.vertexCount,
            indexCount: meshBuffers.indexCount,
            splatCount: splats.count,
            positionBuffer: try makePositionBuffer(for: splats)
        )
    }

    private static func downsampleSplatsIfNeeded(_ splats: [GSSplatData]) -> [GSSplatData] {
        let limit = maxRenderableSplats
        guard limit > 0, splats.count > limit else {
            return splats
        }

        var sampled: [GSSplatData] = []
        sampled.reserveCapacity(limit)
        let step = Double(splats.count) / Double(limit)
        var cursor = 0.0

        for _ in 0..<limit {
            let index = min(Int(cursor), splats.count - 1)
            sampled.append(splats[index])
            cursor += step
        }

        return sampled
    }

    private static func makePositionBuffer(for splats: [GSSplatData]) throws -> MTLBuffer {
        guard let device else {
            throw GSError.invalidPLYData("Metal device unavailable while creating GPU sort buffers.")
        }

        let splatCount = splats.count
        guard let positionBuffer = device.makeBuffer(
            length: splatCount * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ) else {
            throw GSError.invalidPLYData("Unable to allocate position buffer for GPU sorting.")
        }

        let positionPointer = positionBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: splatCount)
        for (index, splat) in splats.enumerated() {
            positionPointer[index] = splat.position
        }

        return positionBuffer
    }
    private static func envInt(_ key: String, defaultValue: Int) -> Int {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let parsed = Int(raw) else {
            return defaultValue
        }
        return max(0, parsed)
    }
}
