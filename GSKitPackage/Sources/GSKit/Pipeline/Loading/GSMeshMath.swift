import Darwin
import Foundation
import simd

@available(macOS 26.0, *)
@inline(__always)
func require(_ props: [String: GSPLYProperty], _ name: String) throws -> GSPLYProperty {
    guard let property = props[name] else {
        throw GSError.missingPLYProperty(name)
    }
    return property
}

@available(macOS 26.0, *)
@inline(__always)
func readFloat(_ record: UnsafeRawPointer, _ prop: GSPLYProperty) -> Float {
    switch prop.type {
    case .float32: return record.loadUnaligned(fromByteOffset: prop.offset, as: Float.self)
    case .float64: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: Double.self))
    case .int8: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: Int8.self))
    case .uint8: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: UInt8.self))
    case .int16: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: Int16.self))
    case .uint16: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: UInt16.self))
    case .int32: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: Int32.self))
    case .uint32: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: UInt32.self))
    case .int64: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: Int64.self))
    case .uint64: return Float(record.loadUnaligned(fromByteOffset: prop.offset, as: UInt64.self))
    }
}

@available(macOS 26.0, *)
@inline(__always)
func sigmoid(_ x: Float) -> Float {
    1.0 / (1.0 + Darwin.exp(-x))
}

@available(macOS 26.0, *)
@inline(__always)
func clamp01(_ value: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(
        min(max(value.x, 0), 1),
        min(max(value.y, 0), 1),
        min(max(value.z, 0), 1)
    )
}

@available(macOS 26.0, *)
@inline(__always)
func srgbToLinearApprox01(_ srgb: SIMD3<Float>) -> SIMD3<Float> {
    let clamped = clamp01(srgb)
    return SIMD3<Float>(
        Darwin.powf(clamped.x, 2.2),
        Darwin.powf(clamped.y, 2.2),
        Darwin.powf(clamped.z, 2.2)
    )
}

@available(macOS 26.0, *)
@inline(__always)
func normalizedQuaternion(x: Float, y: Float, z: Float, w: Float) -> simd_quatf {
    var quaternion = simd_quatf(ix: x, iy: y, iz: z, r: w)
    if simd_dot(quaternion.vector, quaternion.vector) > 0 {
        quaternion = simd_normalize(quaternion)
    } else {
        quaternion = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    }
    return quaternion
}

@available(macOS 26.0, *)
@inline(__always)
func majorAxes(rotation quaternion: simd_quatf, sigma: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
    var majorIndex = 0
    var majorSigma = sigma.x
    var minorIndex = 1
    var minorSigma = sigma.y

    if minorSigma > majorSigma {
        swap(&majorIndex, &minorIndex)
        swap(&majorSigma, &minorSigma)
    }

    let thirdSigma = sigma.z
    if thirdSigma > majorSigma {
        minorIndex = majorIndex
        minorSigma = majorSigma
        majorIndex = 2
        majorSigma = thirdSigma
    } else if thirdSigma > minorSigma {
        minorIndex = 2
        minorSigma = thirdSigma
    }

    return (
        quaternion.act(basisVector(majorIndex)) * max(majorSigma, 1e-6),
        quaternion.act(basisVector(minorIndex)) * max(minorSigma, 1e-6)
    )
}

@available(macOS 26.0, *)
@inline(__always)
func basisVector(_ axisIndex: Int) -> SIMD3<Float> {
    switch axisIndex {
    case 0: return SIMD3<Float>(1, 0, 0)
    case 1: return SIMD3<Float>(0, 1, 0)
    default: return SIMD3<Float>(0, 0, 1)
    }
}
