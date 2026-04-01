import Foundation
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

@MainActor
final class GSSortingSystem: System {
    static let splatQuery = EntityQuery(where: .has(GSSortComponent.self) && .has(GSModelDataComponent.self))

    var lastSortTimes: [ObjectIdentifier: CFAbsoluteTime] = [:]
    var lastCameraPositions: [ObjectIdentifier: SIMD3<Float>] = [:]
    var lastCameraForwards: [ObjectIdentifier: SIMD3<Float>] = [:]
    var sortTask: Task<Void, Never>?

    var localBoundsCache: [ObjectIdentifier: LocalBounds] = [:]
    var renderableSplatCountCache: [ObjectIdentifier: Int] = [:]
    var renderBudgetRatioCache: [ObjectIdentifier: Float] = [:]
    var budgetFpsEstimateCache: [ObjectIdentifier: Float] = [:]
    var budgetLowFpsStreakCache: [ObjectIdentifier: Int] = [:]
    var budgetHighFpsStreakCache: [ObjectIdentifier: Int] = [:]
    var lastBudgetAdjustTimes: [ObjectIdentifier: CFAbsoluteTime] = [:]

    required init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let splatEntities = Array(context.entities(matching: Self.splatQuery, updatingSystemWhen: .rendering))
        guard let camera = GSCameraState.resolve(from: context) else { return }
        let frameDeltaTime = Float(max(context.deltaTime, 1.0 / 240.0))

        for entity in splatEntities {
            guard let sortComponent = entity.components[GSSortComponent.self],
                  sortComponent.isEnabled,
                  let modelData = entity.components[GSModelDataComponent.self] else {
                continue
            }

            let entityID = ObjectIdentifier(entity)
            let totalCount = modelData.splatCount
            guard totalCount > 0 else { continue }

            let modelEntity = GSModelEntityResolver.resolve(for: entity)
            let localCamera = camera.localSpace(relativeTo: modelEntity.transformMatrix(relativeTo: nil).inverse)
            let localCameraPos = localCamera.position
            let localCameraForward = localCamera.forward

            // Consume completed background sort result
            if let result = Self.consumePendingSortResult(for: entityID) {
                let renderBudgetRatio = currentRenderBudgetRatio(for: entityID)
                let budgetCount = Self.quantizeActiveCount(
                    max(1, min(totalCount, Int(Float(result.indices.count) * renderBudgetRatio))),
                    totalCount: totalCount
                )

                updateRenderableMeshPart(
                    for: entityID,
                    lowLevelMesh: modelData.lowLevelMesh,
                    baseParts: modelData.meshParts,
                    activeSplatCount: budgetCount,
                    totalSplatCount: totalCount
                )

                Self.writeSortedIndices(result.indices, activeCount: budgetCount, to: modelData.lowLevelMesh)
            }

            // Check if we should trigger a new sort
            let positionDelta = distance(
                localCameraPos,
                lastCameraPositions[entityID] ?? SIMD3<Float>(.infinity, .infinity, .infinity)
            )
            let forwardDelta = dot(
                localCameraForward,
                lastCameraForwards[entityID] ?? SIMD3<Float>(.infinity, .infinity, .infinity)
            )
            let now = CFAbsoluteTimeGetCurrent()
            let elapsedSinceLastSort = now - (lastSortTimes[entityID] ?? 0)

            let cameraMoved = !(positionDelta < Self.cameraPositionEpsilon && forwardDelta > Self.cameraForwardDotThreshold)
            if cameraMoved {
                if elapsedSinceLastSort < Self.sortMinIntervalSeconds { continue }
            } else if elapsedSinceLastSort < Self.sortIdleRefreshSeconds {
                continue
            }

            lastCameraPositions[entityID] = localCameraPos
            lastCameraForwards[entityID] = localCameraForward
            lastSortTimes[entityID] = now

            // Update render budget
            let _ = updateAndGetRenderBudgetRatio(
                for: entityID,
                frameFPS: 1.0 / max(frameDeltaTime, 1.0 / 240.0),
                now: now
            )

            // Snapshot positions for background sort
            let positionPtr = modelData.positionBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: totalCount)
            var positionsCopy = [SIMD3<Float>](repeating: .zero, count: totalCount)
            positionsCopy.withUnsafeMutableBufferPointer { dest in
                dest.baseAddress!.initialize(from: positionPtr, count: totalCount)
            }

            sortTask = Task.detached(priority: .userInitiated) {
                let result = Self.performCpuSort(
                    positions: positionsCopy,
                    cameraPos: localCameraPos,
                    cameraForward: localCameraForward,
                    count: totalCount,
                    entityID: entityID
                )
                Self.submitSortResult(result)
            }
        }
    }
}
