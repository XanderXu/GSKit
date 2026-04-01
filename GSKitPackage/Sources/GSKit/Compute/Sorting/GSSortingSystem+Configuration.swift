import Foundation

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

extension GSSortingSystem {
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
    nonisolated static let activeCountQuantization: Int = max(
        1,
        envInt("GSKIT_ACTIVE_COUNT_QUANTIZATION", defaultValue: 4_096)
    )
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
    nonisolated static let targetFPS: Float = envFloat(
        "GSKIT_TARGET_FPS",
        defaultValue: defaultTargetFPS
    )
    nonisolated static let fpsDeadband: Float = envFloat(
        "GSKIT_FPS_DEADBAND",
        defaultValue: 1.5
    )

    nonisolated private static let defaultCameraPositionEpsilon: Float = 0.01
    nonisolated private static let defaultCameraForwardDotThreshold: Float = 0.9985
    nonisolated private static let defaultSortMinIntervalSeconds: CFTimeInterval = 1.0 / 30.0
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
        return max(0, parsed)
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

    nonisolated static func envDouble(_ key: String, defaultValue: Double) -> Double {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let parsed = Double(raw),
              parsed.isFinite else {
            return defaultValue
        }
        return parsed
    }
}
