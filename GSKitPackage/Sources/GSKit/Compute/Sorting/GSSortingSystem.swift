import Foundation
import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

@MainActor
final class GSSortingSystem: System {
    static let splatQuery = EntityQuery(where: .has(GSSortComponent.self) && .has(GSModelDataComponent.self))

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var sortBuffersA: [ObjectIdentifier: MTLBuffer] = [:]
    var sortBuffersB: [ObjectIdentifier: MTLBuffer] = [:]
    var visibleIndexBuffers: [ObjectIdentifier: MTLBuffer] = [:]
    var visibleIndexIdentityCountCache: [ObjectIdentifier: Int] = [:]
    var histogramBuffers: [ObjectIdentifier: MTLBuffer] = [:]
    var localBoundsCache: [ObjectIdentifier: LocalBounds] = [:]
    var radixPassStateCache: [ObjectIdentifier: RadixPassState] = [:]
    var cullThresholdCache: [ObjectIdentifier: Float] = [:]
    var renderBudgetRatioCache: [ObjectIdentifier: Float] = [:]
    var budgetFpsEstimateCache: [ObjectIdentifier: Float] = [:]
    var budgetLowFpsStreakCache: [ObjectIdentifier: Int] = [:]
    var budgetHighFpsStreakCache: [ObjectIdentifier: Int] = [:]
    var renderableSplatCountCache: [ObjectIdentifier: Int] = [:]
    var activeVisibleCountCache: [ObjectIdentifier: Int] = [:]
    var lastBudgetAdjustTimes: [ObjectIdentifier: CFAbsoluteTime] = [:]
    var lastCompactionPositions: [ObjectIdentifier: SIMD3<Float>] = [:]
    var lastCompactionForwards: [ObjectIdentifier: SIMD3<Float>] = [:]
    var lastCompactionTimes: [ObjectIdentifier: CFAbsoluteTime] = [:]
    var lastSortTimes: [ObjectIdentifier: CFAbsoluteTime] = [:]
    var lastCameraPositions: [ObjectIdentifier: SIMD3<Float>] = [:]
    var lastCameraForwards: [ObjectIdentifier: SIMD3<Float>] = [:]

    var depthPipeline: MTLComputePipelineState?
    var radixCountPipeline: MTLComputePipelineState?
    var radixScanPipeline: MTLComputePipelineState?
    var radixScatterPipeline: MTLComputePipelineState?
    var writeIndicesPipeline: MTLComputePipelineState?

    required init(scene: RealityKit.Scene) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("GSKit: Metal not available for sorting.")
        }
        self.device = device
        self.commandQueue = queue

        do {
            let library = try GSMetalLibrary.makeDefault(device: device)
            guard let depthFunction = library.makeFunction(name: "gskit_calculate_depths"),
                  let countFunction = library.makeFunction(name: "gskit_radix_count"),
                  let scanFunction = library.makeFunction(name: "gskit_radix_scan"),
                  let scatterFunction = library.makeFunction(name: "gskit_radix_scatter"),
                  let writeFunction = library.makeFunction(name: "gskit_write_indices") else {
                fatalError("GSKit: Could not find Metal functions in library.")
            }

            func makePipeline(function: MTLFunction, label: String) throws -> MTLComputePipelineState {
                let descriptor = MTLComputePipelineDescriptor()
                descriptor.label = label
                descriptor.computeFunction = function
                descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
                return try device.makeComputePipelineState(
                    descriptor: descriptor,
                    options: [],
                    reflection: nil
                )
            }

            depthPipeline = try makePipeline(function: depthFunction, label: "GSKit Depth Pipeline")
            radixCountPipeline = try makePipeline(function: countFunction, label: "GSKit Radix Count Pipeline")
            radixScanPipeline = try makePipeline(function: scanFunction, label: "GSKit Radix Scan Pipeline")
            radixScatterPipeline = try makePipeline(function: scatterFunction, label: "GSKit Radix Scatter Pipeline")
            writeIndicesPipeline = try makePipeline(function: writeFunction, label: "GSKit Write Indices Pipeline")
        } catch {
            depthPipeline = nil
            radixCountPipeline = nil
            radixScanPipeline = nil
            radixScatterPipeline = nil
            writeIndicesPipeline = nil
        }
    }

    func update(context: SceneUpdateContext) {
        let splatEntities = Array(context.entities(matching: Self.splatQuery, updatingSystemWhen: .rendering))
        let activeEntityIDs = Set(splatEntities.map { ObjectIdentifier($0) })
        defer {
            cleanupBufferCaches(activeEntityIDs: activeEntityIDs)
        }

        guard let camera = GSCameraState.resolve(from: context) else { return }
        let frameDeltaTime = Float(max(context.deltaTime, 1.0 / 240.0))

        var preparedSorts: [PreparedSort] = []
        preparedSorts.reserveCapacity(splatEntities.count)

        for entity in splatEntities {
            guard let sortComponent = entity.components[GSSortComponent.self],
                  sortComponent.isEnabled,
                  let modelData = entity.components[GSModelDataComponent.self] else {
                continue
            }

            let modelEntity = GSModelEntityResolver.resolve(for: entity)
            let localCamera = camera.localSpace(relativeTo: modelEntity.transformMatrix(relativeTo: nil).inverse)

            if let preparedSort = prepareSortDispatch(
                for: entity,
                with: modelData,
                localCameraPos: localCamera.position,
                localCameraForward: localCamera.forward,
                frameDeltaTime: frameDeltaTime
            ) {
                preparedSorts.append(preparedSort)
            }
        }

        guard !preparedSorts.isEmpty else { return }
        Self.encodeAndCommitSortBatch(preparedSorts)
    }
}
