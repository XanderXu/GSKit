import Foundation
import simd

#if os(visionOS)
import ARKit
import QuartzCore
#endif

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

@MainActor
public final class GSARKitHeadTracker {
    public static let shared = GSARKitHeadTracker()

    #if os(visionOS)
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var isRunning = false

    public func start() async {
        guard !isRunning else { return }
        do {
            try await session.run([worldTracking])
            isRunning = true
        } catch {
            print("GSKit: ARKit session failed to start: \(error)")
        }
    }

    var headTransform: simd_float4x4? {
        guard isRunning else { return nil }
        return worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.originFromAnchorTransform
    }
    #endif
}
