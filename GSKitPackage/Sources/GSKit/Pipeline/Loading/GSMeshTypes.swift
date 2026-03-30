import Foundation
import Metal
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

struct GSMeshBuildResult: @unchecked Sendable {
    let vertexData: Data
    let indexData: Data
    let parts: [LowLevelMesh.Part]
    let vertexCount: Int
    let indexCount: Int
    let splatCount: Int
    let positionBuffer: MTLBuffer
}

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

struct GSSplatData {
    let position: SIMD3<Float>
    let axisU: SIMD3<Float>
    let axisV: SIMD3<Float>
    let rgb: SIMD3<Float>
    let alpha: Float
}

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

struct GSMeshVertex {
    var px: Float
    var py: Float
    var pz: Float
    var u: Float
    var v: Float
    var r: Float
    var g: Float
    var b: Float
    var a: Float
}

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

struct GSQuadMeshBuffers {
    let vertexData: Data
    let indexData: Data
    let parts: [LowLevelMesh.Part]
    let vertexCount: Int
    let indexCount: Int
}
