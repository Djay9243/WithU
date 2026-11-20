//
//  MainTabView.swift
//  WithU
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Map", systemImage: "location.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Circle", systemImage: "person.2.fill", value: AppTab.circle) {
                CircleView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(Theme.primary)
    }
}

#Preview {
    MainTabView()
        .environment(AppModel.shared)
}
