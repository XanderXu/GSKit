import Foundation
import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
extension GSSortingSystem {
    func cleanupBufferCaches(activeEntityIDs: Set<ObjectIdentifier>) {
        let allKeys = Set(sortBuffersA.keys)
            .union(sortBuffersB.keys)
            .union(visibleIndexBuffers.keys)
            .union(visibleIndexIdentityCountCache.keys)
            .union(histogramBuffers.keys)
            .union(depthParamsBuffers.keys)
            .union(radixPassParamsBuffers.keys)
            .union(scanParamsBuffers.keys)
            .union(writeParamsBuffers.keys)
            .union(renderableSplatCountCache.keys)
            .union(activeVisibleCountCache.keys)
            .union(renderBudgetRatioCache.keys)
            .union(budgetFpsEstimateCache.keys)
            .union(budgetLowFpsStreakCache.keys)
            .union(budgetHighFpsStreakCache.keys)
            .union(lastCompactionTimes.keys)
            .union(lastBudgetAdjustTimes.keys)
            .union(lastSortTimes.keys)

        for key in allKeys where !activeEntityIDs.contains(key) {
            sortBuffersA.removeValue(forKey: key)
            sortBuffersB.removeValue(forKey: key)
            visibleIndexBuffers.removeValue(forKey: key)
            visibleIndexIdentityCountCache.removeValue(forKey: key)
            histogramBuffers.removeValue(forKey: key)
            depthParamsBuffers.removeValue(forKey: key)
            radixPassParamsBuffers.removeValue(forKey: key)
            scanParamsBuffers.removeValue(forKey: key)
            writeParamsBuffers.removeValue(forKey: key)
            localBoundsCache.removeValue(forKey: key)
            radixPassStateCache.removeValue(forKey: key)
            cullThresholdCache.removeValue(forKey: key)
            renderBudgetRatioCache.removeValue(forKey: key)
            budgetFpsEstimateCache.removeValue(forKey: key)
            budgetLowFpsStreakCache.removeValue(forKey: key)
            budgetHighFpsStreakCache.removeValue(forKey: key)
            renderableSplatCountCache.removeValue(forKey: key)
            activeVisibleCountCache.removeValue(forKey: key)
            lastBudgetAdjustTimes.removeValue(forKey: key)
            lastCompactionPositions.removeValue(forKey: key)
            lastCompactionForwards.removeValue(forKey: key)
            lastCompactionTimes.removeValue(forKey: key)
            lastSortTimes.removeValue(forKey: key)
            lastCameraPositions.removeValue(forKey: key)
            lastCameraForwards.removeValue(forKey: key)
        }
    }

    func prepareSortDispatch(
        for entity: Entity,
        with data: GSModelDataComponent,
        localCameraPos: SIMD3<Float>,
        localCameraForward: SIMD3<Float>,
        frameDeltaTime: Float
    ) -> PreparedSort? {
        let totalCount = data.splatCount
        guard totalCount > 0 else { return nil }

        let totalPaddedCount = max(256, ((totalCount + 255) / 256) * 256)
        let totalNumGroups = (totalPaddedCount + 255) / 256
        let sortEntrySize = MemoryLayout<SIMD2<UInt32>>.stride
        let sortBufferSize = totalPaddedCount * sortEntrySize
        let visibleIndexBufferSize = totalCount * MemoryLayout<UInt32>.stride
        let histogramSize = 256 * totalNumGroups * MemoryLayout<UInt32>.stride

        let entityID = ObjectIdentifier(entity)
        guard let localBounds = getOrComputeLocalBounds(
            entityID: entityID,
            positionBuffer: data.positionBuffer,
            count: totalCount
        ) else {
            return nil
        }

        let radixPassCount = recommendedRadixPassCount(
            localBounds: localBounds,
            localCameraPos: localCameraPos,
            localCameraForward: localCameraForward
        )
        let stabilizedPassCount = stabilizedRadixPassCount(
            entityID: entityID,
            targetPassCount: radixPassCount
        )

        let positionDelta = distance(
            localCameraPos,
            lastCameraPositions[entityID] ?? SIMD3<Float>(.infinity, .infinity, .infinity)
        )
        let forwardDelta = dot(
            localCameraForward,
            lastCameraForwards[entityID] ?? SIMD3<Float>(.infinity, .infinity, .infinity)
        )
        let now = CFAbsoluteTimeGetCurrent()
        let frameFPS = 1.0 / max(frameDeltaTime, 1.0 / 240.0)
        let elapsedSinceLastSort = now - (lastSortTimes[entityID] ?? 0)

        let cameraMoved = !(positionDelta < Self.cameraPositionEpsilon && forwardDelta > Self.cameraForwardDotThreshold)
        if cameraMoved {
            if elapsedSinceLastSort < Self.sortMinIntervalSeconds {
                return nil
            }
        } else if elapsedSinceLastSort < Self.sortIdleRefreshSeconds {
            return nil
        }

        lastCameraPositions[entityID] = localCameraPos
        lastCameraForwards[entityID] = localCameraForward

        guard let sortBufferA = getOrMakeBuffer(
            from: &sortBuffersA,
            entityID: entityID,
            size: sortBufferSize,
            options: .storageModePrivate
        ), let sortBufferB = getOrMakeBuffer(
            from: &sortBuffersB,
            entityID: entityID,
            size: sortBufferSize,
            options: .storageModePrivate
        ), let visibleIndexBuffer = getOrMakeBuffer(
            from: &visibleIndexBuffers,
            entityID: entityID,
            size: visibleIndexBufferSize,
            options: .storageModeShared
        ), let histogramBuffer = getOrMakeBuffer(
            from: &histogramBuffers,
            entityID: entityID,
            size: histogramSize,
            options: .storageModePrivate
        ) else {
            return nil
        }

        if !Self.useDirectionalCull, visibleIndexIdentityCountCache[entityID] != totalCount {
            Self.fillIdentityVisibleIndices(visibleIndexBuffer: visibleIndexBuffer, count: totalCount)
            visibleIndexIdentityCountCache[entityID] = totalCount
        }

        let cullThreshold = currentCullThreshold(for: entityID)
        let visibleCount: Int
        if Self.useDirectionalCull {
            let shouldRecomputeVisibleSet = shouldRecomputeCompaction(
                entityID: entityID,
                localCameraPos: localCameraPos,
                localCameraForward: localCameraForward,
                now: now
            ) || activeVisibleCountCache[entityID] == nil

            if shouldRecomputeVisibleSet {
                let recomputedActiveCount = compactVisibleSplats(
                    positionBuffer: data.positionBuffer,
                    count: totalCount,
                    localCameraPos: localCameraPos,
                    localCameraForward: localCameraForward,
                    cullThreshold: cullThreshold,
                    outputVisibleIndices: visibleIndexBuffer
                )
                activeVisibleCountCache[entityID] = recomputedActiveCount
                lastCompactionPositions[entityID] = localCameraPos
                lastCompactionForwards[entityID] = localCameraForward
                lastCompactionTimes[entityID] = now
                updateCullThreshold(
                    for: entityID,
                    activeCount: recomputedActiveCount,
                    totalCount: totalCount,
                    currentThreshold: cullThreshold,
                    frameDeltaTime: frameDeltaTime
                )
                visibleCount = recomputedActiveCount
            } else {
                visibleCount = activeVisibleCountCache[entityID] ?? 0
            }
        } else {
            activeVisibleCountCache[entityID] = totalCount
            visibleCount = totalCount
        }
        guard visibleCount > 0 else { return nil }

        let renderBudgetRatio = updateAndGetRenderBudgetRatio(
            for: entityID,
            frameFPS: frameFPS,
            now: now
        )
        let renderBudgetCount = Self.quantizeActiveCount(
            max(1, min(totalCount, Int(Float(totalCount) * renderBudgetRatio))),
            totalCount: totalCount
        )

        var activeCount = visibleCount
        if activeCount > renderBudgetCount {
            Self.downsampleVisibleIndicesInPlace(
                visibleIndexBuffer: visibleIndexBuffer,
                sourceCount: activeCount,
                targetCount: renderBudgetCount
            )
            activeCount = renderBudgetCount
        }
        activeCount = Self.quantizeActiveCount(activeCount, totalCount: totalCount)

        updateRenderableMeshPart(
            for: entityID,
            lowLevelMesh: data.lowLevelMesh,
            baseParts: data.meshParts,
            activeSplatCount: activeCount,
            totalSplatCount: totalCount
        )
        guard activeCount > 0 else { return nil }

        let activePaddedCount = max(256, ((activeCount + 255) / 256) * 256)
        let activeNumGroups = (activePaddedCount + 255) / 256

        guard let depthPipeline,
              let radixCountPipeline,
              let radixScanPipeline,
              let radixScatterPipeline,
              let writeIndicesPipeline else {
            return nil
        }

        guard let depthParamsBuffer = getOrMakeBuffer(
            from: &depthParamsBuffers,
            entityID: entityID,
            size: MemoryLayout<DepthKernelParams>.stride,
            options: .storageModeShared
        ), let radixPassParamsBuffer = getOrMakeBuffer(
            from: &radixPassParamsBuffers,
            entityID: entityID,
            size: MemoryLayout<RadixPassKernelParams>.stride * Self.radixShifts.count,
            options: .storageModeShared
        ), let scanParamsBuffer = getOrMakeBuffer(
            from: &scanParamsBuffers,
            entityID: entityID,
            size: MemoryLayout<RadixScanKernelParams>.stride,
            options: .storageModeShared
        ), let writeParamsBuffer = getOrMakeBuffer(
            from: &writeParamsBuffers,
            entityID: entityID,
            size: MemoryLayout<WriteIndicesKernelParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        var depthParams = DepthKernelParams(
            cameraLocalPos: SIMD4<Float>(localCameraPos.x, localCameraPos.y, localCameraPos.z, 0),
            cameraLocalForward: SIMD4<Float>(localCameraForward.x, localCameraForward.y, localCameraForward.z, 0),
            count: UInt32(activeCount),
            paddedCount: UInt32(activePaddedCount),
            padding0: 0,
            padding1: 0
        )
        memcpy(depthParamsBuffer.contents(), &depthParams, MemoryLayout<DepthKernelParams>.stride)

        var passParams: [RadixPassKernelParams] = []
        passParams.reserveCapacity(Self.radixShifts.count)
        for shift in Self.radixShifts {
            passParams.append(
                RadixPassKernelParams(
                    paddedCount: UInt32(activePaddedCount),
                    shift: shift,
                    numGroups: UInt32(activeNumGroups),
                    padding: 0
                )
            )
        }
        passParams.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            memcpy(radixPassParamsBuffer.contents(), base, raw.count)
        }

        var scanParams = RadixScanKernelParams(
            numGroups: UInt32(activeNumGroups),
            padding0: 0,
            padding1: 0,
            padding2: 0
        )
        memcpy(scanParamsBuffer.contents(), &scanParams, MemoryLayout<RadixScanKernelParams>.stride)

        var writeParams = WriteIndicesKernelParams(
            activeCount: UInt32(activeCount),
            totalCount: UInt32(totalCount),
            padding0: 0,
            padding1: 0
        )
        memcpy(writeParamsBuffer.contents(), &writeParams, MemoryLayout<WriteIndicesKernelParams>.stride)

        let job = SortDispatchJob(
            commandQueue: commandQueue,
            depthPipeline: depthPipeline,
            radixCountPipeline: radixCountPipeline,
            radixScanPipeline: radixScanPipeline,
            radixScatterPipeline: radixScatterPipeline,
            writeIndicesPipeline: writeIndicesPipeline,
            positionBuffer: data.positionBuffer,
            visibleIndicesBuffer: visibleIndexBuffer,
            sortBufferA: sortBufferA,
            sortBufferB: sortBufferB,
            histogramBuffer: histogramBuffer,
            depthParamsBuffer: depthParamsBuffer,
            radixPassParamsBuffer: radixPassParamsBuffer,
            scanParamsBuffer: scanParamsBuffer,
            writeParamsBuffer: writeParamsBuffer,
            totalCount: totalCount,
            activeCount: activeCount,
            numGroups: activeNumGroups,
            radixPassCount: stabilizedPassCount
        )

        lastSortTimes[entityID] = now
        return PreparedSort(
            job: job,
            target: SortCompletionTarget(entity: entity, lowLevelMesh: data.lowLevelMesh)
        )
    }

    func getOrMakeBuffer(
        from dictionary: inout [ObjectIdentifier: MTLBuffer],
        entityID: ObjectIdentifier,
        size: Int,
        options: MTLResourceOptions
    ) -> MTLBuffer? {
        if let existing = dictionary[entityID], existing.length >= size {
            return existing
        }
        guard let newBuffer = device.makeBuffer(length: size, options: options) else {
            return nil
        }
        dictionary[entityID] = newBuffer
        return newBuffer
    }
}

@available(macOS 26.0, *)
extension GSSortingSystem {
    struct LocalBounds {
        let center: SIMD3<Float>
        let extent: SIMD3<Float>
    }

    struct RadixPassState {
        var currentPassCount: Int
        var increaseStreak: Int
        var decreaseStreak: Int
    }
}
