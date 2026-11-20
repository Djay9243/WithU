//
//  WithUApp.swift
//  WithU
//
//  Created by Syed Jahanzaib Ali Zaidi on 16/11/2026.
//

import AppIntents
import SwiftUI

@main
struct WithUApp: App {
    @State private var model = AppModel.shared

    init() {
        WithUShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
    }
}
