import Metal
import RealityKit

@MainActor
@available(macOS 26.0, *)
enum GSGaussianMaterialFactory {
   
//    static func makeGaussianMaterial(device: MTLDevice) throws -> CustomMaterial {
//        let library = try GSMetalLibrary.makeDefault(device: device)
//        let surfaceShader = CustomMaterial.SurfaceShader(
//            named: "gskit_gaussian_surface",
//            in: library
//        )
//
//        var material = try CustomMaterial(
//            surfaceShader: surfaceShader,
//            lightingModel: .unlit
//        )
//        // The package now renders splats through a single CustomMaterial path.
//        material.blending = .transparent(opacity: .init(scale: 1.0))
//        material.opacityThreshold = 0
//        material.faceCulling = .none
//        material.readsDepth = true
//        material.writesDepth = false
//        return material
//    }
}
