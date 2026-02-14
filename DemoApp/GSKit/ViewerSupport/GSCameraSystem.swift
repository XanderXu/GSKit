import Foundation
import RealityKit
import simd

@MainActor
final class GSCameraSystem: System {
    private static let cameraQuery = EntityQuery(where: .has(PerspectiveCameraComponent.self))

    private var flyPosition = SIMD3<Float>(0, 0, 3)
    private var flyYaw: Float = 0.0
    private var flyPitch: Float = 0.0

    required init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let cameras = context.entities(
            matching: Self.cameraQuery,
            updatingSystemWhen: .rendering
        )
        guard let camera = cameras.first(where: { _ in true }) else {
            return
        }

        let input = GSInputManager.shared
        let deltaTime = Float(context.deltaTime)

        updateFlyCamera(camera, input: input, dt: deltaTime)
        input.resetDeltas()
    }

    private func updateFlyCamera(_ camera: Entity, input: GSInputManager, dt: Float) {
        if input.isRightDragging {
            flyYaw -= input.mouseDeltaX * 0.005
            flyPitch -= input.mouseDeltaY * 0.005
        }

        let keyLookSpeed: Float = 2.0 * dt
        if input.rotateLeft { flyYaw += keyLookSpeed }
        if input.rotateRight { flyYaw -= keyLookSpeed }

        let halfPi = Float.pi / 2.0 - 0.01
        flyPitch = max(-halfPi, min(halfPi, flyPitch))

        let yawRotation = simd_quatf(angle: flyYaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchRotation = simd_quatf(angle: flyPitch, axis: SIMD3<Float>(1, 0, 0))
        let rotation = yawRotation * pitchRotation

        camera.transform.rotation = rotation

        let localForward = rotation.act(SIMD3<Float>(0, 0, -1))
        let localRight = rotation.act(SIMD3<Float>(1, 0, 0))
        let moveSpeed: Float = 5.0 * dt

        if input.forward { flyPosition += localForward * moveSpeed }
        if input.backward { flyPosition -= localForward * moveSpeed }
        if input.left { flyPosition -= localRight * moveSpeed }
        if input.right { flyPosition += localRight * moveSpeed }
        if input.up { flyPosition += SIMD3<Float>(0, 1, 0) * moveSpeed }
        if input.down { flyPosition -= SIMD3<Float>(0, 1, 0) * moveSpeed }

        camera.transform.translation = flyPosition
    }
}
