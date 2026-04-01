import Foundation
import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

extension GSSortingSystem {
    struct LocalBounds {
        let center: SIMD3<Float>
        let extent: SIMD3<Float>
    }

    func getOrComputeLocalBounds(
        entityID: ObjectIdentifier,
        positionBuffer: MTLBuffer,
        count: Int
    ) -> LocalBounds? {
        if let cached = localBoundsCache[entityID] {
            return cached
        }
        guard count > 0 else { return nil }

        let positions = positionBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: count)
        var minPosition = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxPosition = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for index in 0..<count {
            let position = positions[index]
            minPosition = simd_min(minPosition, position)
            maxPosition = simd_max(maxPosition, position)
        }

        let bounds = LocalBounds(
            center: (minPosition + maxPosition) * 0.5,
            extent: (maxPosition - minPosition) * 0.5
        )
        localBoundsCache[entityID] = bounds
        return bounds
    }

    nonisolated static func quantizeActiveCount(_ count: Int, totalCount: Int) -> Int {
        let clamped = max(1, min(count, totalCount))
        let quantization = max(1, activeCountQuantization)
        if clamped == totalCount { return totalCount }
        if clamped <= quantization { return clamped }
        let quantized = (clamped / quantization) * quantization
        return max(1, min(quantized, totalCount))
    }

    func updateRenderableMeshPart(
        for entityID: ObjectIdentifier,
        lowLevelMesh: LowLevelMesh,
        baseParts: [LowLevelMesh.Part],
        activeSplatCount: Int,
        totalSplatCount: Int
    ) {
        guard !baseParts.isEmpty else { return }
        let clampedActiveCount = max(0, min(activeSplatCount, totalSplatCount))
        if renderableSplatCountCache[entityID] == clampedActiveCount {
            return
        }
        renderableSplatCountCache[entityID] = clampedActiveCount

        let templatePart = baseParts[0]
        lowLevelMesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexOffset: templatePart.indexOffset,
                indexCount: clampedActiveCount * 6,
                topology: templatePart.topology,
                materialIndex: templatePart.materialIndex,
                bounds: templatePart.bounds
            )
        ])
    }
}
