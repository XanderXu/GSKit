//
//  GSKitApp.swift
//  GSKit
//

import SwiftUI
import GSKit
import RealityKit

@main
struct GSKitApp: App {
    @State private var appState = AppState()

    init() {
        GSKitRuntime.registerSystems()
        GSCameraSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
