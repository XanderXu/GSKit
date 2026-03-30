//
//  ContentView.swift
//  GSKit_visionOS
//
//  Created by XanderXu on 2026/3/30.
//

import SwiftUI
import RealityKit

struct ContentView: View {

    var body: some View {
        VStack {
            

            Text("Hello, world!")

            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
