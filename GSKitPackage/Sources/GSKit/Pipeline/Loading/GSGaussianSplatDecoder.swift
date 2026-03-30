import Foundation
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

enum GSGaussianSplatDecoder {
    static func decode(
        from ply: GSPLYFile,
        xProp: GSPLYProperty,
        yProp: GSPLYProperty,
        zProp: GSPLYProperty
    ) async throws -> [GSSplatData] {
        let props = ply.header.properties
        guard let opacityProp = props["opacity"] ?? props["alpha"] else {
            throw GSError.missingPLYProperty("opacity (or alpha)")
        }

        let layout = try GaussianPropertyLayout(
            xProp: xProp,
            yProp: yProp,
            zProp: zProp,
            opacityProp: opacityProp,
            scale0Prop: require(props, "scale_0"),
            scale1Prop: require(props, "scale_1"),
            scale2Prop: require(props, "scale_2"),
            rot0Prop: require(props, "rot_0"),
            rot1Prop: require(props, "rot_1"),
            rot2Prop: require(props, "rot_2"),
            rot3Prop: require(props, "rot_3"),
            sh0Prop: props["f_dc_0"],
            sh1Prop: props["f_dc_1"],
            sh2Prop: props["f_dc_2"],
            redProp: props["red"],
            greenProp: props["green"],
            blueProp: props["blue"]
        )

        return try await decodeSplats(from: ply, layout: layout)
    }

    private static func decodeSplats(
        from ply: GSPLYFile,
        layout: GaussianPropertyLayout
    ) async throws -> [GSSplatData] {
        let vertexCount = ply.header.vertexCount
        let processorCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let targetChunkSize = max(100_000, vertexCount / processorCount)
        let chunkCount = max(1, (vertexCount + targetChunkSize - 1) / targetChunkSize)

        return try await withThrowingTaskGroup(of: [GSSplatData].self) { group in
            for chunkIndex in 0..<chunkCount {
                group.addTask {
                    let startIndex = chunkIndex * targetChunkSize
                    let endIndex = min(startIndex + targetChunkSize, vertexCount)
                    var localSplats: [GSSplatData] = []
                    localSplats.reserveCapacity(endIndex - startIndex)

                    try ply.data.withUnsafeBytes { raw in
                        guard let fileBase = raw.baseAddress else {
                            throw GSError.invalidPLYData("File bytes are unavailable.")
                        }
                        let recordBase = fileBase.advanced(by: ply.header.vertexDataOffset)

                        for recordIndex in startIndex..<endIndex {
                            if recordIndex & 8191 == 0 { try Task.checkCancellation() }
                            let record = recordBase.advanced(by: recordIndex * ply.header.vertexStride)

                            let splat = if layout.useFloat32FastPath {
                                makeFastSplat(record: record, layout: layout)
                            } else {
                                makeDynamicSplat(record: record, layout: layout)
                            }

                            if let splat {
                                localSplats.append(splat)
                            }
                        }
                    }

                    return localSplats
                }
            }

            var combined: [GSSplatData] = []
            combined.reserveCapacity(vertexCount)
            for try await chunk in group {
                combined.append(contentsOf: chunk)
            }
            return combined
        }
    }

    private static func makeFastSplat(
        record: UnsafeRawPointer,
        layout: GaussianPropertyLayout
    ) -> GSSplatData? {
        let center = SIMD3<Float>(
            record.loadUnaligned(fromByteOffset: layout.xOffset, as: Float.self),
            record.loadUnaligned(fromByteOffset: layout.yOffset, as: Float.self),
            record.loadUnaligned(fromByteOffset: layout.zOffset, as: Float.self)
        )
        let alpha = sigmoid(record.loadUnaligned(fromByteOffset: layout.opacityOffset, as: Float.self))
        let sigma = SIMD3<Float>(
            exp(record.loadUnaligned(fromByteOffset: layout.scale0Offset, as: Float.self)),
            exp(record.loadUnaligned(fromByteOffset: layout.scale1Offset, as: Float.self)),
            exp(record.loadUnaligned(fromByteOffset: layout.scale2Offset, as: Float.self))
        )
        let quaternion = normalizedQuaternion(
            x: record.loadUnaligned(fromByteOffset: layout.rotXOffset, as: Float.self),
            y: record.loadUnaligned(fromByteOffset: layout.rotYOffset, as: Float.self),
            z: record.loadUnaligned(fromByteOffset: layout.rotZOffset, as: Float.self),
            w: record.loadUnaligned(fromByteOffset: layout.rotWOffset, as: Float.self)
        )

        let srgb: SIMD3<Float>
        if let sh0Offset = layout.sh0Offset,
           let sh1Offset = layout.sh1Offset,
           let sh2Offset = layout.sh2Offset,
           layout.shAreFloat32 {
            let sh = SIMD3<Float>(
                record.loadUnaligned(fromByteOffset: sh0Offset, as: Float.self),
                record.loadUnaligned(fromByteOffset: sh1Offset, as: Float.self),
                record.loadUnaligned(fromByteOffset: sh2Offset, as: Float.self)
            )
            srgb = clamp01(SIMD3<Float>(repeating: 0.5) + (sh * 0.28209))
        } else if let redOffset = layout.redOffset,
                  let greenOffset = layout.greenOffset,
                  let blueOffset = layout.blueOffset,
                  layout.rgbAreUInt8 {
            srgb = SIMD3<Float>(
                Float(record.loadUnaligned(fromByteOffset: redOffset, as: UInt8.self)) / 255.0,
                Float(record.loadUnaligned(fromByteOffset: greenOffset, as: UInt8.self)) / 255.0,
                Float(record.loadUnaligned(fromByteOffset: blueOffset, as: UInt8.self)) / 255.0
            )
        } else {
            srgb = SIMD3<Float>(repeating: 1)
        }

        return makeSplat(center: center, alpha: alpha, sigma: sigma, quaternion: quaternion, srgb: srgb)
    }

    private static func makeDynamicSplat(
        record: UnsafeRawPointer,
        layout: GaussianPropertyLayout
    ) -> GSSplatData? {
        let center = SIMD3<Float>(
            readFloat(record, layout.xProp),
            readFloat(record, layout.yProp),
            readFloat(record, layout.zProp)
        )
        let alpha = sigmoid(readFloat(record, layout.opacityProp))
        let sigma = SIMD3<Float>(
            exp(readFloat(record, layout.scale0Prop)),
            exp(readFloat(record, layout.scale1Prop)),
            exp(readFloat(record, layout.scale2Prop))
        )
        let quaternion = normalizedQuaternion(
            x: readFloat(record, layout.rot1Prop),
            y: readFloat(record, layout.rot2Prop),
            z: readFloat(record, layout.rot3Prop),
            w: readFloat(record, layout.rot0Prop)
        )

        let srgb: SIMD3<Float>
        if let sh0Prop = layout.sh0Prop,
           let sh1Prop = layout.sh1Prop,
           let sh2Prop = layout.sh2Prop {
            let sh = SIMD3<Float>(
                readFloat(record, sh0Prop),
                readFloat(record, sh1Prop),
                readFloat(record, sh2Prop)
            )
            srgb = clamp01(SIMD3<Float>(repeating: 0.5) + (sh * 0.28209))
        } else if let redProp = layout.redProp,
                  let greenProp = layout.greenProp,
                  let blueProp = layout.blueProp {
            srgb = clamp01(
                SIMD3<Float>(
                    readFloat(record, redProp) / 255.0,
                    readFloat(record, greenProp) / 255.0,
                    readFloat(record, blueProp) / 255.0
                )
            )
        } else {
            srgb = SIMD3<Float>(repeating: 1)
        }

        return makeSplat(center: center, alpha: alpha, sigma: sigma, quaternion: quaternion, srgb: srgb)
    }

    private static func makeSplat(
        center: SIMD3<Float>,
        alpha: Float,
        sigma: SIMD3<Float>,
        quaternion: simd_quatf,
        srgb: SIMD3<Float>
    ) -> GSSplatData? {
        guard !center.x.isNaN, !center.y.isNaN, !center.z.isNaN else {
            return nil
        }

        let (axisU, axisV) = majorAxes(rotation: quaternion, sigma: sigma)
        return GSSplatData(
            position: center,
            axisU: axisU,
            axisV: axisV,
            rgb: srgbToLinearApprox01(srgb),
            alpha: alpha
        )
    }
}

@available(macOS 26.0, *)
private struct GaussianPropertyLayout {
    let xProp: GSPLYProperty
    let yProp: GSPLYProperty
    let zProp: GSPLYProperty
    let opacityProp: GSPLYProperty
    let scale0Prop: GSPLYProperty
    let scale1Prop: GSPLYProperty
    let scale2Prop: GSPLYProperty
    let rot0Prop: GSPLYProperty
    let rot1Prop: GSPLYProperty
    let rot2Prop: GSPLYProperty
    let rot3Prop: GSPLYProperty
    let sh0Prop: GSPLYProperty?
    let sh1Prop: GSPLYProperty?
    let sh2Prop: GSPLYProperty?
    let redProp: GSPLYProperty?
    let greenProp: GSPLYProperty?
    let blueProp: GSPLYProperty?

    let xOffset: Int
    let yOffset: Int
    let zOffset: Int
    let opacityOffset: Int
    let scale0Offset: Int
    let scale1Offset: Int
    let scale2Offset: Int
    let rotWOffset: Int
    let rotXOffset: Int
    let rotYOffset: Int
    let rotZOffset: Int
    let sh0Offset: Int?
    let sh1Offset: Int?
    let sh2Offset: Int?
    let redOffset: Int?
    let greenOffset: Int?
    let blueOffset: Int?
    let useFloat32FastPath: Bool
    let shAreFloat32: Bool
    let rgbAreUInt8: Bool

    init(
        xProp: GSPLYProperty,
        yProp: GSPLYProperty,
        zProp: GSPLYProperty,
        opacityProp: GSPLYProperty,
        scale0Prop: GSPLYProperty,
        scale1Prop: GSPLYProperty,
        scale2Prop: GSPLYProperty,
        rot0Prop: GSPLYProperty,
        rot1Prop: GSPLYProperty,
        rot2Prop: GSPLYProperty,
        rot3Prop: GSPLYProperty,
        sh0Prop: GSPLYProperty?,
        sh1Prop: GSPLYProperty?,
        sh2Prop: GSPLYProperty?,
        redProp: GSPLYProperty?,
        greenProp: GSPLYProperty?,
        blueProp: GSPLYProperty?
    ) throws {
        self.xProp = xProp
        self.yProp = yProp
        self.zProp = zProp
        self.opacityProp = opacityProp
        self.scale0Prop = scale0Prop
        self.scale1Prop = scale1Prop
        self.scale2Prop = scale2Prop
        self.rot0Prop = rot0Prop
        self.rot1Prop = rot1Prop
        self.rot2Prop = rot2Prop
        self.rot3Prop = rot3Prop
        self.sh0Prop = sh0Prop
        self.sh1Prop = sh1Prop
        self.sh2Prop = sh2Prop
        self.redProp = redProp
        self.greenProp = greenProp
        self.blueProp = blueProp

        xOffset = xProp.offset
        yOffset = yProp.offset
        zOffset = zProp.offset
        opacityOffset = opacityProp.offset
        scale0Offset = scale0Prop.offset
        scale1Offset = scale1Prop.offset
        scale2Offset = scale2Prop.offset
        rotWOffset = rot0Prop.offset
        rotXOffset = rot1Prop.offset
        rotYOffset = rot2Prop.offset
        rotZOffset = rot3Prop.offset
        sh0Offset = sh0Prop?.offset
        sh1Offset = sh1Prop?.offset
        sh2Offset = sh2Prop?.offset
        redOffset = redProp?.offset
        greenOffset = greenProp?.offset
        blueOffset = blueProp?.offset

        useFloat32FastPath = [
            xProp, yProp, zProp, opacityProp,
            scale0Prop, scale1Prop, scale2Prop,
            rot0Prop, rot1Prop, rot2Prop, rot3Prop
        ].allSatisfy { $0.type == .float32 }

        shAreFloat32 = {
            guard let sh0Prop, let sh1Prop, let sh2Prop else { return false }
            return sh0Prop.type == .float32
                && sh1Prop.type == .float32
                && sh2Prop.type == .float32
        }()

        rgbAreUInt8 = {
            guard let redProp, let greenProp, let blueProp else { return false }
            return redProp.type == .uint8
                && greenProp.type == .uint8
                && blueProp.type == .uint8
        }()
    }
}
