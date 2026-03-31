import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

extension GSSortingSystem {
    static func encodeAndCommitSortBatch(_ sorts: [PreparedSort]) {
        guard !sorts.isEmpty,
              let commandBuffer = sorts[0].job.commandQueue.makeCommandBuffer() else {
            return
        }

        commandBuffer.label = "GSKit Sort Batch"
        var didEncodeWork = false

        for preparedSort in sorts {
            guard preparedSort.target.entity != nil else { continue }
            let destinationIndexBuffer = preparedSort.target.lowLevelMesh.replaceIndices(using: commandBuffer)
            didEncodeWork = encodeDirectSort(
                job: preparedSort.job,
                destinationIndexBuffer: destinationIndexBuffer,
                into: commandBuffer
            ) || didEncodeWork
        }

        guard didEncodeWork else { return }
        commandBuffer.commit()
    }

    nonisolated static func encodeDirectSort(
        job: SortDispatchJob,
        destinationIndexBuffer: MTLBuffer,
        into commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let threadGroupSize = 256
        let threadsPerThreadgroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)
        let countGroups = MTLSize(width: job.numGroups, height: 1, depth: 1)
        let writeGroupCount = max(1, (job.activeCount + threadGroupSize - 1) / threadGroupSize)
        let writeGroups = MTLSize(width: writeGroupCount, height: 1, depth: 1)

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        encoder.label = "GSKit Sort Pipeline"

        // --- Depth Pass ---
        encoder.setComputePipelineState(job.depthPipeline)
        encoder.setBuffer(job.positionBuffer, offset: 0, index: 0)
        encoder.setBuffer(job.visibleIndicesBuffer, offset: 0, index: 1)
        encoder.setBuffer(job.sortBufferA, offset: 0, index: 2)
        var depthParams = job.depthParams
        encoder.setBytes(&depthParams, length: MemoryLayout<DepthKernelParams>.stride, index: 3)
        encoder.dispatchThreadgroups(countGroups, threadsPerThreadgroup: threadsPerThreadgroup)

        // --- Radix Sort Passes ---
        var currentSourceBuffer = job.sortBufferA
        var currentDestBuffer = job.sortBufferB
        let passCount = max(minAdaptiveRadixPassCount, min(job.radixPassCount, radixShifts.count))

        for pass in 0..<passCount {
            // Count
            encoder.setComputePipelineState(job.radixCountPipeline)
            encoder.setBuffer(currentSourceBuffer, offset: 0, index: 0)
            encoder.setBuffer(job.histogramBuffer, offset: 0, index: 1)
            var passParams = job.radixPassParams[pass]
            encoder.setBytes(&passParams, length: MemoryLayout<RadixPassKernelParams>.stride, index: 2)
            encoder.dispatchThreadgroups(countGroups, threadsPerThreadgroup: threadsPerThreadgroup)

            // Scan
            encoder.setComputePipelineState(job.radixScanPipeline)
            encoder.setBuffer(job.histogramBuffer, offset: 0, index: 0)
            var scanParams = job.scanParams
            encoder.setBytes(&scanParams, length: MemoryLayout<RadixScanKernelParams>.stride, index: 1)
            encoder.dispatchThreadgroups(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: threadsPerThreadgroup
            )

            // Scatter
            encoder.setComputePipelineState(job.radixScatterPipeline)
            encoder.setBuffer(currentSourceBuffer, offset: 0, index: 0)
            encoder.setBuffer(currentDestBuffer, offset: 0, index: 1)
            encoder.setBuffer(job.histogramBuffer, offset: 0, index: 2)
            var scatterParams = job.radixPassParams[pass]
            encoder.setBytes(&scatterParams, length: MemoryLayout<RadixPassKernelParams>.stride, index: 3)
            encoder.dispatchThreadgroups(countGroups, threadsPerThreadgroup: threadsPerThreadgroup)

            swap(&currentSourceBuffer, &currentDestBuffer)
        }

        // --- Write Indices ---
        encoder.setComputePipelineState(job.writeIndicesPipeline)
        encoder.setBuffer(currentSourceBuffer, offset: 0, index: 0)
        encoder.setBuffer(destinationIndexBuffer, offset: 0, index: 1)
        var writeParams = job.writeParams
        encoder.setBytes(&writeParams, length: MemoryLayout<WriteIndicesKernelParams>.stride, index: 2)
        encoder.dispatchThreadgroups(writeGroups, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.endEncoding()
        return true
    }
}

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

extension GSSortingSystem {
    struct DepthKernelParams {
        var cameraLocalPos: SIMD4<Float>
        var cameraLocalForward: SIMD4<Float>
        var count: UInt32
        var paddedCount: UInt32
        var padding0: UInt32
        var padding1: UInt32
    }

    struct RadixPassKernelParams {
        var paddedCount: UInt32
        var shift: UInt32
        var numGroups: UInt32
        var padding: UInt32
    }

    struct RadixScanKernelParams {
        var numGroups: UInt32
        var padding0: UInt32
        var padding1: UInt32
        var padding2: UInt32
    }

    struct WriteIndicesKernelParams {
        var activeCount: UInt32
        var padding0: UInt32
        var padding1: UInt32
        var padding2: UInt32
    }

    struct CullKernelParams {
        var cameraLocalPos: SIMD4<Float>
        var cameraLocalForward: SIMD4<Float>
        var cullThreshold: Float
        var cullDistanceScale: Float
        var totalCount: UInt32
        var padding: UInt32
    }

    struct PreparedSort: @unchecked Sendable {
        let job: SortDispatchJob
        let target: SortCompletionTarget
    }

    final class SortCompletionTarget: @unchecked Sendable {
        weak var entity: Entity?
        let lowLevelMesh: LowLevelMesh

        init(entity: Entity, lowLevelMesh: LowLevelMesh) {
            self.entity = entity
            self.lowLevelMesh = lowLevelMesh
        }
    }

    struct SortDispatchJob: @unchecked Sendable {
        let commandQueue: MTLCommandQueue
        let depthPipeline: MTLComputePipelineState
        let radixCountPipeline: MTLComputePipelineState
        let radixScanPipeline: MTLComputePipelineState
        let radixScatterPipeline: MTLComputePipelineState
        let writeIndicesPipeline: MTLComputePipelineState
        let positionBuffer: MTLBuffer
        let visibleIndicesBuffer: MTLBuffer
        let sortBufferA: MTLBuffer
        let sortBufferB: MTLBuffer
        let histogramBuffer: MTLBuffer
        let depthParams: DepthKernelParams
        let radixPassParams: [RadixPassKernelParams]
        let scanParams: RadixScanKernelParams
        let writeParams: WriteIndicesKernelParams
        let activeCount: Int
        let numGroups: Int
        let radixPassCount: Int
    }
}
