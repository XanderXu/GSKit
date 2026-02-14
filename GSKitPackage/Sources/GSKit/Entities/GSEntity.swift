//
//  GSEntity.swift
//  GSKit
//

import Foundation
import RealityKit

@available(macOS 26.0, *)
@MainActor
public final class GSEntity: Entity {
    public let sourceURL: URL
    public let modelEntity: ModelEntity

    init(sourceURL: URL, modelEntity: ModelEntity) {
        self.sourceURL = sourceURL
        self.modelEntity = modelEntity
        super.init()
        self.name = sourceURL.lastPathComponent
        self.modelEntity.name = "GSModel"
        self.addChild(self.modelEntity)
    }

    @MainActor
    required init() {
        self.sourceURL = URL(fileURLWithPath: "/")
        self.modelEntity = ModelEntity()
        super.init()
        self.modelEntity.name = "GSModel"
        self.addChild(self.modelEntity)
    }

    public static func load(
        url: URL
    ) async throws -> GSEntity {
        try await GSEntityLoader.load(url: url)
    }
}
