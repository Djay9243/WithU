//
//  MainTabView.swift
//  WithU
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: tabSelection) {
            Tab("Map", systemImage: "location.circle.fill", value: AppTab.map) {
                MapScreen()
            }
            Tab("Journal", systemImage: "book.fill", value: AppTab.journal) {
                JournalView()
            }
            Tab("Circle", systemImage: "person.2.fill", value: AppTab.circle) {
                CircleView()
            }
            // The round search icon on its own at the right of the tab bar.
            // `.prominent` gives it that look without the system search field
            // (which would sit at the bottom). It never becomes the selected
            // tab (see `tabSelection`), so its content is never shown.
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .prominent) {
                Color.clear
            }
        }
        .tint(Theme.primary)
        .sheet(isPresented: $model.showingSearch) {
            DestinationSearchView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
    }

    /// Tapping the search icon opens search as a sheet, with its field at the
    /// top, and stays on the current tab. A search tab would move the field
    /// to the bottom of the screen.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { model.selectedTab },
            set: { tab in
                if tab == .search {
                    model.showingSearch = true
                } else {
                    model.selectedTab = tab
                }
            }
        )
    }
}

#Preview {
    MainTabView()
        .environment(AppModel.shared)
}
