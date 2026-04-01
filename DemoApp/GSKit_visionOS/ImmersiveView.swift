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
        .task() {
            await requestAuthorization()
        }
        
    }
    func requestAuthorization() async {
        let session = SpatialTrackingSession()
        let configuration = SpatialTrackingSession.Configuration(tracking: [.world])
        let unapprovedCapabilities = await session.run(configuration)
        if let unapprovedCapabilities, unapprovedCapabilities.anchor.contains(.world) {
            // AnchorEntities 仍然可以保持追踪，并保持视觉效果更新
            // 但是，AnchorEntity.transform 将不会接收到更新
            debugPrint("User has rejected world data for your app.")
        } else {
            // AnchorEntity.transform 将会报告手部锚点位置和姿态
            debugPrint("User has approved world data for your app.\nAnchorEntity.transform will report anchor pose")
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
