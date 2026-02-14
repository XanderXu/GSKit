import Foundation

@available(macOS 26.0, *)
enum GSPLYParser {
    static func load(url: URL) async throws -> GSPLYFile {
        let data = try Data(contentsOf: url, options: [.alwaysMapped])
        let header = try parseHeader(from: data)
        return GSPLYFile(url: url, data: data, header: header)
    }

    private static func parseHeader(from data: Data) throws -> GSPLYHeader {
        let scanPrefix = data.prefix(1_048_576)
        guard let endHeaderRange = scanPrefix.range(of: Data("end_header".utf8)) else {
            throw GSError.invalidPLYHeader("Missing end_header marker.")
        }

        let afterMarker = endHeaderRange.upperBound
        let headerEndIndex: Data.Index
        if let newline = scanPrefix[afterMarker...].firstIndex(where: { $0 == 0x0A }) {
            headerEndIndex = scanPrefix.index(after: newline)
        } else {
            headerEndIndex = afterMarker
        }

        let headerBytes = scanPrefix[..<headerEndIndex]
        let headerText = String(decoding: headerBytes, as: UTF8.self)

        var vertexCount: Int?
        var inVertexElement = false
        var currentOffset = 0
        var properties: [String: GSPLYProperty] = [:]

        var totalOffsetBeforeVertex = 0
        var currentElementStride = 0
        var currentElementCount = 0
        var foundVertex = false
        var sawFormat = false

        for rawLine in headerText.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line == "ply" || line.hasPrefix("comment") {
                continue
            }

            if line.hasPrefix("format ") {
                sawFormat = true
                let parts = line.split(separator: " ")
                guard parts.count >= 3 else {
                    throw GSError.invalidPLYHeader("Malformed format line.")
                }
                guard parts[1] == "binary_little_endian" else {
                    throw GSError.unsupportedPLYFormat(String(parts[1]))
                }
                continue
            }

            if line.hasPrefix("element ") {
                if !foundVertex {
                    totalOffsetBeforeVertex += currentElementCount * currentElementStride
                }

                let parts = line.split(separator: " ")
                guard parts.count >= 3 else {
                    throw GSError.invalidPLYHeader("Malformed element line.")
                }

                let elementName = parts[1]
                let count = Int(parts[2]) ?? 0
                currentElementCount = count
                currentElementStride = 0

                inVertexElement = elementName == "vertex"
                if inVertexElement {
                    foundVertex = true
                    vertexCount = count
                    currentOffset = 0
                    properties.removeAll(keepingCapacity: true)
                }
                continue
            }

            if line.hasPrefix("property ") {
                let parts = line.split(separator: " ")
                guard parts.count >= 3 else {
                    throw GSError.invalidPLYHeader("Malformed property line.")
                }

                if parts[1] == "list" {
                    if inVertexElement {
                        throw GSError.invalidPLYHeader("List properties are not supported in the vertex element.")
                    }
                    throw GSError.invalidPLYHeader("List properties in elements preceding 'vertex' are not supported.")
                }

                guard let scalarType = GSPLYScalarType.parse(plyToken: parts[1]) else {
                    throw GSError.invalidPLYHeader("Unsupported property type '\(parts[1])'.")
                }

                currentElementStride += scalarType.byteCount
                if inVertexElement {
                    let name = String(parts[2])
                    properties[name] = GSPLYProperty(type: scalarType, offset: currentOffset)
                    currentOffset += scalarType.byteCount
                }
                continue
            }

            if line == "end_header" {
                break
            }
        }

        guard sawFormat else {
            throw GSError.invalidPLYHeader("Missing format line.")
        }
        guard let vertexCount else {
            throw GSError.missingPLYVertexElement
        }
        guard currentOffset > 0 else {
            throw GSError.invalidPLYHeader("Vertex stride is zero.")
        }

        let vertexDataOffset = headerBytes.count + totalOffsetBeforeVertex
        let expectedByteCount = vertexDataOffset + (vertexCount * currentOffset)
        guard data.count >= expectedByteCount else {
            throw GSError.invalidPLYData("File is smaller than header-declared vertex data.")
        }

        return GSPLYHeader(
            vertexCount: vertexCount,
            vertexStride: currentOffset,
            vertexDataOffset: vertexDataOffset,
            properties: properties
        )
    }
}
