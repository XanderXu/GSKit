//
//  GSKit_visionOSApp.swift
//  GSKit_visionOS
//
//  Created by XanderXu on 2026/3/30.
//

import SwiftUI
import GSKit

@main
struct GSKit_visionOSApp: App {

    @State private var appModel = AppModel()

    init() {
        GSKitRuntime.registerSystems()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
//        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        .immersionStyle(selection: .constant(.progressive(0.1...1, initialAmount: 0.5)), in: .progressive)
    }
}
