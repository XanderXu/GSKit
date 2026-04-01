import Foundation
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

extension GSSortingSystem {

    // MARK: - Render Budget

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
}
