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
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                MapScreen()
            }
            Tab("Journal", systemImage: "book.fill", value: AppTab.journal) {
                JournalView()
            }
            Tab("Circle", systemImage: "person.2.fill", value: AppTab.circle) {
                CircleView()
            }
        }
        .tint(Theme.primary)
    }
}

#Preview {
    MainTabView()
        .environment(AppModel.shared)
}
