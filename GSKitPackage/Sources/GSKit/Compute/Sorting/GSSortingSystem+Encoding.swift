import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
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
        let finalCountsGroup = MTLSize(
            width: (job.totalCount + threadGroupSize - 1) / threadGroupSize,
            height: 1,
            depth: 1
        )

        guard let depthEncoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        depthEncoder.label = "GSKit Direct Depth Pass"
        depthEncoder.setComputePipelineState(job.depthPipeline)
        depthEncoder.setBuffer(job.positionBuffer, offset: 0, index: 0)
        depthEncoder.setBuffer(job.visibleIndicesBuffer, offset: 0, index: 1)
        depthEncoder.setBuffer(job.sortBufferA, offset: 0, index: 2)
        depthEncoder.setBuffer(job.depthParamsBuffer, offset: 0, index: 3)
        depthEncoder.dispatchThreadgroups(countGroups, threadsPerThreadgroup: threadsPerThreadgroup)
        depthEncoder.endEncoding()

        var currentSourceBuffer = job.sortBufferA
        var currentDestBuffer = job.sortBufferB
        let passCount = max(minAdaptiveRadixPassCount, min(job.radixPassCount, radixShifts.count))

        for pass in 0..<passCount {
            let passOffset = pass * MemoryLayout<RadixPassKernelParams>.stride

            guard let countEncoder = commandBuffer.makeComputeCommandEncoder() else { return false }
            countEncoder.label = "GSKit Direct Radix Count"
            countEncoder.setComputePipelineState(job.radixCountPipeline)
            countEncoder.setBuffer(currentSourceBuffer, offset: 0, index: 0)
            countEncoder.setBuffer(job.histogramBuffer, offset: 0, index: 1)
            countEncoder.setBuffer(job.radixPassParamsBuffer, offset: passOffset, index: 2)
            countEncoder.dispatchThreadgroups(countGroups, threadsPerThreadgroup: threadsPerThreadgroup)
            countEncoder.endEncoding()

            guard let scanEncoder = commandBuffer.makeComputeCommandEncoder() else { return false }
            scanEncoder.label = "GSKit Direct Radix Scan"
            scanEncoder.setComputePipelineState(job.radixScanPipeline)
            scanEncoder.setBuffer(job.histogramBuffer, offset: 0, index: 0)
            scanEncoder.setBuffer(job.scanParamsBuffer, offset: 0, index: 1)
            scanEncoder.dispatchThreadgroups(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: threadsPerThreadgroup
            )
            scanEncoder.endEncoding()

            guard let scatterEncoder = commandBuffer.makeComputeCommandEncoder() else { return false }
            scatterEncoder.label = "GSKit Direct Radix Scatter"
            scatterEncoder.setComputePipelineState(job.radixScatterPipeline)
            scatterEncoder.setBuffer(currentSourceBuffer, offset: 0, index: 0)
            scatterEncoder.setBuffer(currentDestBuffer, offset: 0, index: 1)
            scatterEncoder.setBuffer(job.histogramBuffer, offset: 0, index: 2)
            scatterEncoder.setBuffer(job.radixPassParamsBuffer, offset: passOffset, index: 3)
            scatterEncoder.dispatchThreadgroups(countGroups, threadsPerThreadgroup: threadsPerThreadgroup)
            scatterEncoder.endEncoding()

            swap(&currentSourceBuffer, &currentDestBuffer)
        }

        guard let writeEncoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        writeEncoder.label = "GSKit Direct Write Indices"
        writeEncoder.setComputePipelineState(job.writeIndicesPipeline)
        writeEncoder.setBuffer(currentSourceBuffer, offset: 0, index: 0)
        writeEncoder.setBuffer(destinationIndexBuffer, offset: 0, index: 1)
        writeEncoder.setBuffer(job.writeParamsBuffer, offset: 0, index: 2)
        writeEncoder.dispatchThreadgroups(finalCountsGroup, threadsPerThreadgroup: threadsPerThreadgroup)
        writeEncoder.endEncoding()

        return true
    }
}

@available(macOS 26.0, *)
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
        var totalCount: UInt32
        var padding0: UInt32
        var padding1: UInt32
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
        let depthParamsBuffer: MTLBuffer
        let radixPassParamsBuffer: MTLBuffer
        let scanParamsBuffer: MTLBuffer
        let writeParamsBuffer: MTLBuffer
        let totalCount: Int
        let activeCount: Int
        let numGroups: Int
        let radixPassCount: Int
    }
}
