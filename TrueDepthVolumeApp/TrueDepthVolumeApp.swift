//
//  TrueDepthVolumeApp.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 6/16/25.
//

import SwiftUI

@main
struct TrueDepthVolumeApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TrueDepthCameraView()
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text("3D Volume")
                }
        }
    }
}
