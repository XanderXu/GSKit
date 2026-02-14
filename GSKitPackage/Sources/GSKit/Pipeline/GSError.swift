//
//  GSError.swift
//  GSKit
//
//  Created by Tom Krikorian on 14/02/2026.
//

import Foundation

@available(macOS 26.0, *)
enum GSError: LocalizedError {
    case invalidPLYHeader(String)
    case unsupportedPLYFormat(String)
    case missingPLYVertexElement
    case missingPLYProperty(String)
    case invalidPLYData(String)
    case unsupportedStrategy(String)

    var errorDescription: String? {
        switch self {
        case .invalidPLYHeader(let reason):
            return "Invalid PLY header: \(reason)"
        case .unsupportedPLYFormat(let format):
            return "Unsupported PLY format: \(format)"
        case .missingPLYVertexElement:
            return "PLY file is missing an 'element vertex' section."
        case .missingPLYProperty(let name):
            return "PLY file is missing required vertex property '\(name)'."
        case .invalidPLYData(let reason):
            return "Invalid PLY data: \(reason)"
        case .unsupportedStrategy(let reason):
            return "Unsupported render strategy: \(reason)"
        }
    }
}
