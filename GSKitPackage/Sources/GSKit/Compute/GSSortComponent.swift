//
//  GSSortComponent.swift
//  GSKit
//
//  Created by Tom Krikorian on 14/02/2026.
//

import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)
struct GSSortComponent: Component, Sendable {
    var isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}
