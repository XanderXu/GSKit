import Foundation
import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
extension GSSortingSystem {
    func currentRenderBudgetRatio(for entityID: ObjectIdentifier) -> Float {
        let minRatio = min(Self.minRenderBudgetRatio, Self.maxRenderBudgetRatio)
        let maxRatio = max(Self.minRenderBudgetRatio, Self.maxRenderBudgetRatio)
        if let cached = renderBudgetRatioCache[entityID] {
            return max(minRatio, min(cached, maxRatio))
        }
        return max(minRatio, min(Self.defaultRenderBudgetRatio, maxRatio))
    }

    func updateAndGetRenderBudgetRatio(
        for entityID: ObjectIdentifier,
        frameFPS: Float,
        now: CFAbsoluteTime
    ) -> Float {
        let minRatio = min(Self.minRenderBudgetRatio, Self.maxRenderBudgetRatio)
        let maxRatio = max(Self.minRenderBudgetRatio, Self.maxRenderBudgetRatio)
        let fixedBaseRatio = max(minRatio, min(Self.defaultRenderBudgetRatio, maxRatio))

        guard Self.adaptiveRenderBudgetEnabled else {
            renderBudgetRatioCache[entityID] = fixedBaseRatio
            budgetFpsEstimateCache[entityID] = frameFPS
            budgetLowFpsStreakCache[entityID] = 0
            budgetHighFpsStreakCache[entityID] = 0
            return fixedBaseRatio
        }

        var ratio = currentRenderBudgetRatio(for: entityID)
        let lastUpdate = lastBudgetAdjustTimes[entityID] ?? 0
        guard now - lastUpdate >= Self.budgetAdaptIntervalSeconds else {
            return ratio
        }
        lastBudgetAdjustTimes[entityID] = now

        let priorEstimate = budgetFpsEstimateCache[entityID] ?? frameFPS
        let alpha = max(0.01, min(Self.budgetFpsEmaAlpha, 1.0))
        let fpsEstimate = priorEstimate + (frameFPS - priorEstimate) * alpha
        budgetFpsEstimateCache[entityID] = fpsEstimate

        let lowThreshold = Self.targetFPS - Self.fpsDeadband
        let highThreshold = Self.targetFPS + Self.fpsDeadband
        var lowFpsStreak = budgetLowFpsStreakCache[entityID] ?? 0
        var highFpsStreak = budgetHighFpsStreakCache[entityID] ?? 0

        if fpsEstimate < lowThreshold {
            lowFpsStreak += 1
            highFpsStreak = 0
        } else if fpsEstimate > highThreshold {
            highFpsStreak += 1
            lowFpsStreak = 0
        } else {
            lowFpsStreak = max(0, lowFpsStreak - 1)
            highFpsStreak = max(0, highFpsStreak - 1)
        }

        budgetLowFpsStreakCache[entityID] = lowFpsStreak
        budgetHighFpsStreakCache[entityID] = highFpsStreak

        let error = Self.targetFPS - fpsEstimate
        let normalizedError = max(-1.0, min(1.0, error / max(Self.targetFPS, 1.0)))
        if normalizedError > 0, lowFpsStreak >= Self.budgetLowFpsSustainSteps {
            ratio -= normalizedError * Self.fpsBudgetDownGain
        } else if normalizedError < 0, highFpsStreak >= Self.budgetHighFpsRecoverySteps {
            ratio += (-normalizedError) * Self.fpsBudgetUpGain
        }

        ratio = max(minRatio, min(ratio, maxRatio))
        renderBudgetRatioCache[entityID] = ratio
        return ratio
    }

    func shouldRecomputeCompaction(
        entityID: ObjectIdentifier,
        localCameraPos: SIMD3<Float>,
        localCameraForward: SIMD3<Float>,
        now: CFAbsoluteTime
    ) -> Bool {
        guard let lastPos = lastCompactionPositions[entityID],
              let lastForward = lastCompactionForwards[entityID] else {
            return true
        }

        let elapsed = now - (lastCompactionTimes[entityID] ?? 0)
        let movedDistance = distance(localCameraPos, lastPos)
        let forwardDot = dot(localCameraForward, lastForward)
        let hasMovedOrTurned = movedDistance >= Self.compactionPositionEpsilon
            || forwardDot <= Self.compactionForwardDotThreshold

        if hasMovedOrTurned && elapsed >= Self.compactionMinIntervalSeconds {
            return true
        }
        return elapsed >= Self.compactionIdleRefreshSeconds
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

    func compactVisibleSplats(
        positionBuffer: MTLBuffer,
        count: Int,
        localCameraPos: SIMD3<Float>,
        localCameraForward: SIMD3<Float>,
        cullThreshold: Float,
        outputVisibleIndices: MTLBuffer
    ) -> Int {
        guard count > 0 else { return 0 }
        return Self.compactVisibleSplatsParallel(
            positionBuffer: positionBuffer,
            count: count,
            localCameraPos: localCameraPos,
            localCameraForward: localCameraForward,
            cullThreshold: cullThreshold,
            outputVisibleIndices: outputVisibleIndices
        )
    }

    nonisolated static func compactVisibleSplatsParallel(
        positionBuffer: MTLBuffer,
        count: Int,
        localCameraPos: SIMD3<Float>,
        localCameraForward: SIMD3<Float>,
        cullThreshold: Float,
        outputVisibleIndices: MTLBuffer
    ) -> Int {
        let positions = positionBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: count)
        let visibleIndices = outputVisibleIndices.contents().bindMemory(to: UInt32.self, capacity: count)
        let chunkSize = max(1, Self.compactionWorkChunkSize)
        let chunkCount = max(1, (count + chunkSize - 1) / chunkSize)
        let visibilityFlags = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        visibilityFlags.initialize(repeating: 0, count: count)
        defer {
            visibilityFlags.deinitialize(count: count)
            visibilityFlags.deallocate()
        }

        let positionsRef = UnsafeReadablePointer(pointer: UnsafePointer(positions))
        let visibleIndicesRef = UnsafeWritablePointer(pointer: visibleIndices)
        let visibilityFlagsRef = UnsafeWritablePointer(pointer: visibilityFlags)

        let chunkVisibleCounts = UnsafeMutablePointer<Int>.allocate(capacity: chunkCount)
        chunkVisibleCounts.initialize(repeating: 0, count: chunkCount)
        defer {
            chunkVisibleCounts.deinitialize(count: chunkCount)
            chunkVisibleCounts.deallocate()
        }
        let chunkVisibleCountsRef = UnsafeWritablePointer(pointer: chunkVisibleCounts)

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let start = chunk * chunkSize
            let end = min(start + chunkSize, count)
            var localCount = 0

            for splatIndex in start..<end where isSplatVisible(
                positionsRef.pointer[splatIndex],
                localCameraPos: localCameraPos,
                localCameraForward: localCameraForward,
                cullThreshold: cullThreshold
            ) {
                visibilityFlagsRef.pointer[splatIndex] = 1
                localCount += 1
            }

            chunkVisibleCountsRef.pointer[chunk] = localCount
        }

        let chunkWriteOffsets = UnsafeMutablePointer<Int>.allocate(capacity: chunkCount)
        chunkWriteOffsets.initialize(repeating: 0, count: chunkCount)
        defer {
            chunkWriteOffsets.deinitialize(count: chunkCount)
            chunkWriteOffsets.deallocate()
        }

        var visibleCount = 0
        for chunk in 0..<chunkCount {
            chunkWriteOffsets[chunk] = visibleCount
            visibleCount += chunkVisibleCounts[chunk]
        }
        let chunkWriteOffsetsRef = UnsafeReadablePointer(pointer: UnsafePointer(chunkWriteOffsets))

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let start = chunk * chunkSize
            let end = min(start + chunkSize, count)
            var writeIndex = chunkWriteOffsetsRef.pointer[chunk]

            for splatIndex in start..<end where visibilityFlagsRef.pointer[splatIndex] != 0 {
                visibleIndicesRef.pointer[writeIndex] = UInt32(splatIndex)
                writeIndex += 1
            }
        }

        return visibleCount
    }

    nonisolated static func downsampleVisibleIndicesInPlace(
        visibleIndexBuffer: MTLBuffer,
        sourceCount: Int,
        targetCount: Int
    ) {
        guard targetCount > 0, sourceCount > targetCount else { return }
        let visibleIndices = visibleIndexBuffer.contents().bindMemory(to: UInt32.self, capacity: sourceCount)
        let samplingStep = Double(sourceCount) / Double(targetCount)
        var sampleCursor = 0.0

        for outIndex in 0..<targetCount {
            let sourceIndex = min(sourceCount - 1, Int(sampleCursor))
            visibleIndices[outIndex] = visibleIndices[sourceIndex]
            sampleCursor += samplingStep
        }
    }

    nonisolated static func fillIdentityVisibleIndices(
        visibleIndexBuffer: MTLBuffer,
        count: Int
    ) {
        guard count > 0 else { return }
        let visibleIndices = visibleIndexBuffer.contents().bindMemory(to: UInt32.self, capacity: count)
        for index in 0..<count {
            visibleIndices[index] = UInt32(index)
        }
    }

    nonisolated static func quantizeActiveCount(_ count: Int, totalCount: Int) -> Int {
        let clamped = max(1, min(count, totalCount))
        let quantization = max(1, activeCountQuantization)
        if clamped == totalCount { return totalCount }
        if clamped <= quantization { return clamped }
        let quantized = (clamped / quantization) * quantization
        return max(1, min(quantized, totalCount))
    }

    nonisolated static func isSplatVisible(
        _ splatPosition: SIMD3<Float>,
        localCameraPos: SIMD3<Float>,
        localCameraForward: SIMD3<Float>,
        cullThreshold: Float
    ) -> Bool {
        let delta = splatPosition - localCameraPos
        let distanceSquared = max(simd_length_squared(delta), 1e-6)
        let inverseDistance = 1.0 / (1.0 + Self.cullDistanceScale * distanceSquared)
        let direction = delta * rsqrt(distanceSquared)
        let facing = dot(direction, localCameraForward)
        let visibility = max(0.0, min(1.0, 0.5 + 0.5 * facing))
        return (inverseDistance * visibility) >= cullThreshold
    }

    func currentCullThreshold(for entityID: ObjectIdentifier) -> Float {
        let minThreshold = min(Self.minCullControlThreshold, Self.maxCullControlThreshold)
        let maxThreshold = max(Self.minCullControlThreshold, Self.maxCullControlThreshold)
        if let cached = cullThresholdCache[entityID] {
            return max(minThreshold, min(cached, maxThreshold))
        }
        return max(minThreshold, min(Self.defaultCullControlThreshold, maxThreshold))
    }

    func updateCullThreshold(
        for entityID: ObjectIdentifier,
        activeCount: Int,
        totalCount: Int,
        currentThreshold: Float,
        frameDeltaTime: Float
    ) {
        let minThreshold = min(Self.minCullControlThreshold, Self.maxCullControlThreshold)
        let maxThreshold = max(Self.minCullControlThreshold, Self.maxCullControlThreshold)
        var updatedThreshold = max(minThreshold, min(currentThreshold, maxThreshold))
        let activeRatio = totalCount > 0 ? Float(activeCount) / Float(totalCount) : 1.0

        let frameFPS = 1.0 / max(frameDeltaTime, 1.0 / 240.0)
        let fpsError = Self.targetFPS - frameFPS
        if abs(fpsError) > Self.fpsDeadband {
            if fpsError > 0 {
                if activeRatio > Self.minActiveRatio {
                    updatedThreshold += fpsError * Self.fpsCullAdaptGain
                }
            } else {
                updatedThreshold += fpsError * Self.fpsCullRecoveryGain
            }
        }

        if let targetRatio = Self.targetVisibleRatio, totalCount > 0 {
            let ratioError = (Float(activeCount) / Float(totalCount)) - targetRatio
            updatedThreshold += ratioError * Self.cullAdaptRate
        }

        if activeRatio < Self.minActiveRatio {
            let deficit = Self.minActiveRatio - activeRatio
            updatedThreshold -= max(0.01, deficit * 0.20)
        }

        cullThresholdCache[entityID] = max(minThreshold, min(updatedThreshold, maxThreshold))
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

    func recommendedRadixPassCount(
        localBounds: LocalBounds,
        localCameraPos: SIMD3<Float>,
        localCameraForward: SIMD3<Float>
    ) -> Int {
        let centerDepth = dot(localBounds.center - localCameraPos, localCameraForward)
        let projectedHalfExtent =
            abs(localCameraForward.x) * localBounds.extent.x +
            abs(localCameraForward.y) * localBounds.extent.y +
            abs(localCameraForward.z) * localBounds.extent.z

        let minDepth = centerDepth - projectedHalfExtent
        let maxDepth = centerDepth + projectedHalfExtent
        let minKey = UInt32(min(max((minDepth + 10_000.0) * 1_000.0, 0.0), Float(UInt32.max)))
        let maxKey = UInt32(min(max((maxDepth + 10_000.0) * 1_000.0, 0.0), Float(UInt32.max)))
        return (minKey ^ maxKey) <= 0x3FFFF
            ? Self.minAdaptiveRadixPassCount
            : Self.maxAdaptiveRadixPassCount
    }

    func stabilizedRadixPassCount(
        entityID: ObjectIdentifier,
        targetPassCount: Int
    ) -> Int {
        let clampedTarget = max(
            Self.minAdaptiveRadixPassCount,
            min(targetPassCount, Self.maxAdaptiveRadixPassCount)
        )

        guard var state = radixPassStateCache[entityID] else {
            let initial = RadixPassState(
                currentPassCount: clampedTarget,
                increaseStreak: 0,
                decreaseStreak: 0
            )
            radixPassStateCache[entityID] = initial
            return initial.currentPassCount
        }

        if clampedTarget > state.currentPassCount {
            state.increaseStreak += 1
            state.decreaseStreak = 0
            let increaseThreshold = (clampedTarget - state.currentPassCount) >= 2 ? 1 : 2
            if state.increaseStreak >= increaseThreshold {
                state.currentPassCount += 1
                state.increaseStreak = 0
            }
        } else if clampedTarget < state.currentPassCount {
            state.decreaseStreak += 1
            state.increaseStreak = 0
            let decreaseThreshold = (state.currentPassCount - clampedTarget) >= 2 ? 2 : 6
            if state.decreaseStreak >= decreaseThreshold {
                state.currentPassCount -= 1
                state.decreaseStreak = 0
            }
        } else {
            state.increaseStreak = 0
            state.decreaseStreak = 0
        }

        state.currentPassCount = max(
            Self.minAdaptiveRadixPassCount,
            min(state.currentPassCount, Self.maxAdaptiveRadixPassCount)
        )
        radixPassStateCache[entityID] = state
        return state.currentPassCount
    }
}

@available(macOS 26.0, *)
extension GSSortingSystem {
    struct UnsafeReadablePointer<Pointee>: @unchecked Sendable {
        let pointer: UnsafePointer<Pointee>
    }

    struct UnsafeWritablePointer<Pointee>: @unchecked Sendable {
        let pointer: UnsafeMutablePointer<Pointee>
    }
}
