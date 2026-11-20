//
//  WithUWatchApp.swift
//  WithU Watch
//

import SwiftUI

@main
struct WithUWatchApp: App {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Shake detection runs while WithU is on screen.
                    model.setForeground(phase == .active)
                }
        }
    }
}
