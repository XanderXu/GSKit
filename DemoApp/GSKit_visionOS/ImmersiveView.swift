//
//  ImmersiveView.swift
//  GSKit_visionOS
//
//  Created by XanderXu on 2026/3/30.
//

import SwiftUI
import RealityKit
import GSKit


struct ImmersiveView: View {

    @State private var modelEntity: GSEntity?
    @State private var loadState: LoadState = .idle

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "GSRoot"

            let cameraAnchor = AnchorEntity(.head, trackingMode: .continuous)
            var cameraComp = PerspectiveCameraComponent()
            cameraComp.near = 0.05
            cameraComp.far = 100.0
            cameraAnchor.components.set(cameraComp)
            root.addChild(cameraAnchor)

            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "GSRoot" }) else { return }

            if let entity = modelEntity {
                let staleModels = root.children.filter { $0 is GSEntity && $0 !== entity }
                for stale in staleModels {
                    stale.removeFromParent()
                }

                if entity.parent !== root {
                    root.addChild(entity)
                }
            } else {
                let staleModels = root.children.filter { $0 is GSEntity }
                for stale in staleModels {
                    stale.removeFromParent()
                }
            }
        }
        .task() {
            await loadModel()
        }
        
    }
    @MainActor
    private func loadModel() async {
        loadState = .loading
        modelEntity = nil

        do {
            let entity = try await GSEntity.load(url: Bundle.main.url(forResource: "IMG_9738", withExtension: "ply")!)
            guard !Task.isCancelled else { return }
            modelEntity = entity
//            modelEntity?.position = SIMD3<Float>(0, 1, 0)
//            modelEntity?.scale = SIMD3<Float>(0.01, 0.01, 0.01)
            loadState = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            // `localizedDescription` is often too lossy for RealityKit load errors.
            loadState = .error(String(reflecting: error))
        }
    }

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }
}

#Preview(immersionStyle: .full) {
    
}
