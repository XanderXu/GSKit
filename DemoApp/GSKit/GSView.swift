//
//  GSView.swift
//  GSKit
//
//  Created by Tom Krikorian on 14/02/2026.
//

import SwiftUI
import RealityKit
import GSKit

@available(macOS 26.0, *)
struct GSView<Placeholder: View>: View {
    let url: URL
    let placeholder: Placeholder

    @State private var modelEntity: GSEntity?
    @State private var loadState: LoadState = .idle

    init(
        url: URL,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        ZStack {
            RealityView { content in
                let root = Entity()
                root.name = "GSRoot"

                let cameraAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 3))
                var cameraComp = PerspectiveCameraComponent()
                cameraComp.near = 0.01
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

            switch loadState {
            case .idle, .loading:
                placeholder
            case .loaded:
                EmptyView()
            case .error(let message):
                Text("Failed to load: \(message)")
                    .foregroundStyle(.red)
                    .padding()
                    .background(.black.opacity(0.6))
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .task(id: "\(url.path)") {
            await loadModel()
        }
        .onAppear {
            GSInputManager.shared.startMonitoring()
        }
        .onDisappear {
            GSInputManager.shared.stopMonitoring()
        }
    }

    @MainActor
    private func loadModel() async {
        loadState = .loading
        modelEntity = nil

        do {
            let entity = try await GSEntity.load(url: url)
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
