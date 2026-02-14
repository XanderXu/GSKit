import Foundation
import RealityKit
import simd

@available(macOS 26.0, *)
@MainActor
enum GSEntityLoader {
    static func load(url: URL) async throws -> GSEntity {
        let didStartAccess = url.isFileURL ? url.startAccessingSecurityScopedResource() : false
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let meshData = try await Task.detached(priority: .userInitiated) {
            let ply = try await GSPLYParser.load(url: url)
            return try await GSMeshBuilder.buildStaticBakedMeshData(from: ply)
        }.value

        guard let device = GSMeshBuilder.device else {
            throw GSError.invalidPLYData("Metal device unavailable while creating gaussian material.")
        }

        let lowLevelMesh = try GSLowLevelMeshFactory.makeMesh(from: meshData)
        let meshResource = try await MeshResource(from: lowLevelMesh)
        let gaussianMaterial = try GSGaussianMaterialFactory.makeGaussianMaterial(device: device)
        let modelEntity = ModelEntity(mesh: meshResource, materials: [gaussianMaterial])
        modelEntity.transform.rotation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))

        let entity = GSEntity(sourceURL: url, modelEntity: modelEntity)
        entity.components.set(GSSortComponent())
        entity.components.set(
            GSModelDataComponent(
                lowLevelMesh: lowLevelMesh,
                splatCount: meshData.splatCount,
                positionBuffer: meshData.positionBuffer,
                meshParts: meshData.parts
            )
        )

        return entity
    }
}
