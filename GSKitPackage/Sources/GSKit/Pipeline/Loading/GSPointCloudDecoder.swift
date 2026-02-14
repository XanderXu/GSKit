import Foundation
import simd

@available(macOS 26.0, *)
enum GSPointCloudDecoder {
    static func decode(
        from ply: GSPLYFile,
        xProp: GSPLYProperty,
        yProp: GSPLYProperty,
        zProp: GSPLYProperty
    ) async throws -> [GSSplatData] {
        let props = ply.header.properties
        let nxProp = props["nx"]
        let nyProp = props["ny"]
        let nzProp = props["nz"]
        let redProp = props["red"]
        let greenProp = props["green"]
        let blueProp = props["blue"]

        let rgbAreUInt8: Bool = {
            guard let redProp, let greenProp, let blueProp else { return false }
            return redProp.type == .uint8
                && greenProp.type == .uint8
                && blueProp.type == .uint8
        }()

        let vertexCount = ply.header.vertexCount
        let processorCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let targetChunkSize = max(100_000, vertexCount / processorCount)
        let chunkCount = max(1, (vertexCount + targetChunkSize - 1) / targetChunkSize)
        let pointSigma: Float = 0.01
        let axisScale = SIMD3<Float>(repeating: pointSigma)

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
                        let redOffset = redProp?.offset
                        let greenOffset = greenProp?.offset
                        let blueOffset = blueProp?.offset

                        for recordIndex in startIndex..<endIndex {
                            if recordIndex & 8191 == 0 { try Task.checkCancellation() }
                            let record = recordBase.advanced(by: recordIndex * ply.header.vertexStride)

                            let center = SIMD3<Float>(
                                readFloat(record, xProp),
                                readFloat(record, yProp),
                                readFloat(record, zProp)
                            )
                            guard !center.x.isNaN, !center.y.isNaN, !center.z.isNaN else {
                                continue
                            }

                            let srgb: SIMD3<Float>
                            if rgbAreUInt8,
                               let redOffset,
                               let greenOffset,
                               let blueOffset {
                                srgb = SIMD3<Float>(
                                    Float(record.loadUnaligned(fromByteOffset: redOffset, as: UInt8.self)) / 255.0,
                                    Float(record.loadUnaligned(fromByteOffset: greenOffset, as: UInt8.self)) / 255.0,
                                    Float(record.loadUnaligned(fromByteOffset: blueOffset, as: UInt8.self)) / 255.0
                                )
                            } else if let redProp, let greenProp, let blueProp {
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

                            let axes: (SIMD3<Float>, SIMD3<Float>) = {
                                guard let nxProp, let nyProp, let nzProp else {
                                    return (SIMD3<Float>(pointSigma, 0, 0), SIMD3<Float>(0, pointSigma, 0))
                                }

                                let normal = SIMD3<Float>(
                                    readFloat(record, nxProp),
                                    readFloat(record, nyProp),
                                    readFloat(record, nzProp)
                                )
                                let lengthSquared = simd_dot(normal, normal)
                                guard lengthSquared > 1e-12 else {
                                    return (SIMD3<Float>(pointSigma, 0, 0), SIMD3<Float>(0, pointSigma, 0))
                                }

                                return majorAxes(
                                    rotation: simd_quatf(from: SIMD3<Float>(0, 0, 1), to: normal / sqrt(lengthSquared)),
                                    sigma: axisScale
                                )
                            }()

                            localSplats.append(
                                GSSplatData(
                                    position: center,
                                    axisU: axes.0,
                                    axisV: axes.1,
                                    rgb: srgbToLinearApprox01(srgb),
                                    alpha: 1.0
                                )
                            )
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
}
