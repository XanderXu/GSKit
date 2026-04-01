import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

struct GSCameraState {
    private static let cameraQuery = EntityQuery(where: .has(PerspectiveCameraComponent.self))

    let worldPosition: SIMD3<Float>
    let worldForward: SIMD3<Float>

    @MainActor
    static func resolve(from context: SceneUpdateContext) -> GSCameraState? {
        let cameras = context.entities(
            matching: cameraQuery,
            updatingSystemWhen: .rendering
        )
        guard let cameraEntity = cameras.first(where: { _ in true }) else {
            return nil
        }

        let transform = cameraEntity.transformMatrix(relativeTo: nil)
        let worldColumn = transform.columns.3
        print(worldColumn)
        return GSCameraState(
            worldPosition: SIMD3<Float>(worldColumn.x, worldColumn.y, worldColumn.z),
            worldForward: -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
    }

    func localSpace(relativeTo inverseModelMatrix: simd_float4x4) -> GSLocalCameraState {
        let localPosition4 = inverseModelMatrix * SIMD4<Float>(worldPosition.x, worldPosition.y, worldPosition.z, 1.0)
        let localForward4 = inverseModelMatrix * SIMD4<Float>(worldForward.x, worldForward.y, worldForward.z, 0.0)
        let localForward = SIMD3<Float>(localForward4.x, localForward4.y, localForward4.z)
        let normalizedForward = simd_length_squared(localForward) > 0
            ? simd_normalize(localForward)
            : SIMD3<Float>(0, 0, -1)

        return GSLocalCameraState(
            position: SIMD3<Float>(localPosition4.x, localPosition4.y, localPosition4.z),
            forward: normalizedForward
        )
    }
}

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

struct GSLocalCameraState {
    let position: SIMD3<Float>
    let forward: SIMD3<Float>
}

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

@MainActor
enum GSModelEntityResolver {
    static func resolve(for entity: Entity) -> Entity {
        if let splatEntity = entity as? GSEntity {
            return splatEntity.modelEntity
        }
        return entity.children.first(where: { $0 is ModelEntity }) ?? entity
    }
}
