import Foundation

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

extension GSSortingSystem {
    nonisolated static let radixShifts: [UInt32] = [0, 8, 16]
    nonisolated static let minAdaptiveRadixPassCount = 2
    nonisolated static let maxAdaptiveRadixPassCount = 3
    nonisolated static let cameraPositionEpsilon: Float = envFloat(
        "GSKIT_CAMERA_POSITION_EPSILON",
        defaultValue: defaultCameraPositionEpsilon
    )
    nonisolated static let cameraForwardDotThreshold: Float = envFloat(
        "GSKIT_CAMERA_FORWARD_DOT_THRESHOLD",
        defaultValue: defaultCameraForwardDotThreshold
    )
    nonisolated static let sortMinIntervalSeconds: CFTimeInterval = envDouble(
        "GSKIT_SORT_MIN_INTERVAL_SECONDS",
        defaultValue: defaultSortMinIntervalSeconds
    )
    nonisolated static let sortIdleRefreshSeconds: CFTimeInterval = envDouble(
        "GSKIT_SORT_IDLE_REFRESH_SECONDS",
        defaultValue: defaultSortIdleRefreshSeconds
    )
    nonisolated static let useDirectionalCull: Bool = envBool(
        "GSKIT_USE_DIRECTIONAL_CULL",
        defaultValue: false
    )
    nonisolated static let activeCountQuantization: Int = max(
        1,
        envInt("GSKIT_ACTIVE_COUNT_QUANTIZATION", defaultValue: 4_096)
    )
    nonisolated static let cullDistanceScale: Float = 0.05
    nonisolated static let defaultCullControlThreshold: Float = envFloat(
        "GSKIT_CULL_THRESHOLD",
        defaultValue: 0.02
    )
    nonisolated static let minCullControlThreshold: Float = envFloat(
        "GSKIT_MIN_CULL_THRESHOLD",
        defaultValue: 0.01
    )
    nonisolated static let maxCullControlThreshold: Float = envFloat(
        "GSKIT_MAX_CULL_THRESHOLD",
        defaultValue: 0.25
    )
    nonisolated static let minActiveRatio: Float = {
        let ratio = envFloat("GSKIT_MIN_ACTIVE_RATIO", defaultValue: 0.35)
        return max(0.01, min(ratio, 1.0))
    }()
    nonisolated static let defaultRenderBudgetRatio: Float = envFloat(
        "GSKIT_RENDER_BUDGET_RATIO",
        defaultValue: 1.0
    )
    nonisolated static let adaptiveRenderBudgetEnabled: Bool = envBool(
        "GSKIT_ENABLE_ADAPTIVE_RENDER_BUDGET",
        defaultValue: false
    )
    nonisolated static let minRenderBudgetRatio: Float = {
        let ratio = envFloat("GSKIT_MIN_RENDER_BUDGET_RATIO", defaultValue: 0.35)
        return max(0.01, min(ratio, 1.0))
    }()
    nonisolated static let maxRenderBudgetRatio: Float = {
        let ratio = envFloat("GSKIT_MAX_RENDER_BUDGET_RATIO", defaultValue: 1.0)
        return max(0.01, min(ratio, 1.0))
    }()
    nonisolated static let fpsBudgetDownGain: Float = envFloat(
        "GSKIT_FPS_BUDGET_DOWN_GAIN",
        defaultValue: 0.03
    )
    nonisolated static let fpsBudgetUpGain: Float = envFloat(
        "GSKIT_FPS_BUDGET_UP_GAIN",
        defaultValue: 0.02
    )
    nonisolated static let budgetAdaptIntervalSeconds: CFTimeInterval = envDouble(
        "GSKIT_BUDGET_ADAPT_INTERVAL_SECONDS",
        defaultValue: 0.50
    )
    nonisolated static let budgetFpsEmaAlpha: Float = envFloat(
        "GSKIT_BUDGET_FPS_EMA_ALPHA",
        defaultValue: 0.12
    )
    nonisolated static let budgetLowFpsSustainSteps: Int = max(
        1,
        envInt("GSKIT_BUDGET_LOW_FPS_SUSTAIN_STEPS", defaultValue: 6)
    )
    nonisolated static let budgetHighFpsRecoverySteps: Int = max(
        1,
        envInt("GSKIT_BUDGET_HIGH_FPS_RECOVERY_STEPS", defaultValue: 3)
    )
    nonisolated static let cullAdaptRate: Float = envFloat(
        "GSKIT_CULL_ADAPT_RATE",
        defaultValue: 0.035
    )
    nonisolated static let targetVisibleRatio: Float? = envOptionalFloat(
        "GSKIT_TARGET_VISIBLE_RATIO",
        clampedTo: 0.02...1.0
    )
    nonisolated static let targetFPS: Float = envFloat(
        "GSKIT_TARGET_FPS",
        defaultValue: defaultTargetFPS
    )
    nonisolated static let fpsDeadband: Float = envFloat(
        "GSKIT_FPS_DEADBAND",
        defaultValue: 1.5
    )
    nonisolated static let fpsCullAdaptGain: Float = envFloat(
        "GSKIT_FPS_CULL_ADAPT_GAIN",
        defaultValue: 0.01
    )
    nonisolated static let fpsCullRecoveryGain: Float = envFloat(
        "GSKIT_FPS_CULL_RECOVERY_GAIN",
        defaultValue: 0.003
    )
    nonisolated static let compactionPositionEpsilon: Float = envFloat(
        "GSKIT_COMPACTION_POSITION_EPSILON",
        defaultValue: 0.01
    )
    nonisolated static let compactionForwardDotThreshold: Float = envFloat(
        "GSKIT_COMPACTION_FORWARD_DOT_THRESHOLD",
        defaultValue: 0.9985
    )
    nonisolated static let compactionMinIntervalSeconds: CFTimeInterval = envDouble(
        "GSKIT_COMPACTION_MIN_INTERVAL_SECONDS",
        defaultValue: 0.20
    )
    nonisolated static let compactionIdleRefreshSeconds: CFTimeInterval = envDouble(
        "GSKIT_COMPACTION_IDLE_REFRESH_SECONDS",
        defaultValue: 2.00
    )

    nonisolated private static let defaultCameraPositionEpsilon: Float = 0.01
    nonisolated private static let defaultCameraForwardDotThreshold: Float = 0.9985
    nonisolated private static let defaultSortMinIntervalSeconds: CFTimeInterval = 1.0 / 60.0
    nonisolated private static let defaultSortIdleRefreshSeconds: CFTimeInterval = 0.5
    nonisolated private static let defaultTargetFPS: Float = 60.0

    nonisolated static func envFloat(_ key: String, defaultValue: Float) -> Float {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let parsed = Float(raw),
              parsed.isFinite else {
            return defaultValue
        }
        return parsed
    }

    nonisolated static func envInt(_ key: String, defaultValue: Int) -> Int {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let parsed = Int(raw) else {
            return defaultValue
        }
        return parsed
    }

    nonisolated static func envBool(_ key: String, defaultValue: Bool) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key] else {
            return defaultValue
        }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    nonisolated static func envOptionalFloat(
        _ key: String,
        clampedTo bounds: ClosedRange<Float>
    ) -> Float? {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let parsed = Float(raw),
              parsed.isFinite else {
            return nil
        }
        return max(bounds.lowerBound, min(parsed, bounds.upperBound))
    }

    nonisolated static func envDouble(_ key: String, defaultValue: Double) -> Double {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let parsed = Double(raw),
              parsed.isFinite else {
            return defaultValue
        }
        return parsed
    }
}
