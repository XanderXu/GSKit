import Foundation

@available(macOS 26.0, *)
struct GSPLYFile: Sendable {
    let url: URL
    let data: Data
    let header: GSPLYHeader
}

@available(macOS 26.0, *)
struct GSPLYHeader: Sendable {
    let vertexCount: Int
    let vertexStride: Int
    let vertexDataOffset: Int
    let properties: [String: GSPLYProperty]
}

@available(macOS 26.0, *)
struct GSPLYProperty: Sendable {
    let type: GSPLYScalarType
    let offset: Int
}

@available(macOS 26.0, *)
enum GSPLYScalarType: Sendable {
    case float32
    case float64
    case int8
    case uint8
    case int16
    case uint16
    case int32
    case uint32
    case int64
    case uint64

    var byteCount: Int {
        switch self {
        case .float32: 4
        case .float64: 8
        case .int8, .uint8: 1
        case .int16, .uint16: 2
        case .int32, .uint32: 4
        case .int64, .uint64: 8
        }
    }

    static func parse(plyToken: Substring) -> GSPLYScalarType? {
        switch plyToken {
        case "float", "float32": .float32
        case "double", "float64": .float64
        case "char", "int8": .int8
        case "uchar", "uint8": .uint8
        case "short", "int16": .int16
        case "ushort", "uint16": .uint16
        case "int", "int32": .int32
        case "uint", "uint32": .uint32
        case "long", "int64": .int64
        case "ulong", "uint64": .uint64
        default: nil
        }
    }
}
