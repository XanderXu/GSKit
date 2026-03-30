//
//  GSModelDataComponent.swift
//  GSKit
//

import Metal
import RealityKit

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

struct GSModelDataComponent: Component {
    let lowLevelMesh: LowLevelMesh
    let splatCount: Int
    let positionBuffer: MTLBuffer
    let meshParts: [LowLevelMesh.Part]

    init(
        lowLevelMesh: LowLevelMesh,
        splatCount: Int,
        positionBuffer: MTLBuffer,
        meshParts: [LowLevelMesh.Part]
    ) {
        self.lowLevelMesh = lowLevelMesh
        self.splatCount = splatCount
        self.positionBuffer = positionBuffer
        self.meshParts = meshParts
    }
}
