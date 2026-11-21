//
//  DestinationSearchView.swift
//  WithU
//
//  Search, opened from the tab bar's search icon: Apple Maps place and address search, biased to where the
//  person is. Picking a place opens it on the map, ready to start a trip.
//

import SwiftUI

struct DestinationSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var isSearching = false
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(spacing: 12) {
                    searchField
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if isQueryEmpty, !model.savedPlaces.isEmpty {
                                SectionLabel(text: "Saved")
                                savedPlacesRow
                            }
                            if showsRecents {
                                SectionLabel(text: "Recents")
                                    .padding(.top, model.savedPlaces.isEmpty ? 0 : 8)
                            }
                            if isSearching {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 24)
                            } else if let message, !showsRecents, !(isQueryEmpty && !model.savedPlaces.isEmpty) {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 24)
                            }
                            ForEach(showsRecents ? model.recentDestinations : results) { destination in
                                Button {
                                    select(destination)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: model.tag(for: destination)?.symbol
                                              ?? (showsRecents ? "clock.arrow.circlepath" : "mappin.circle.fill"))
                                            .font(.title3)
                                            .foregroundStyle(Theme.primary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(destination.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Theme.ink)
                                            if !destination.subtitle.isEmpty {
                                                Text(destination.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.inkSecondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .card(padding: 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .navigationTitle("Where To?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .task(id: query) {
            await search()
        }
        // Ready to type as soon as search opens.
        .onAppear { focused = true }
    }

    /// At the top of the screen, above saved places and recents.
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSecondary)
            TextField("Search for a place or address", text: $query)
                .focused($focused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(Theme.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
    }

    /// Opens the place on the map with its trip sheet, and clears the search.
    private func select(_ destination: Destination) {
        model.showOnMap(destination)
        query = ""
        results = []
        focused = false
    }

    private var isQueryEmpty: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Recent places are shown until the person starts typing.
    private var showsRecents: Bool {
        isQueryEmpty && !model.recentDestinations.isEmpty
    }

    /// Home, Work and Gym, when tagged: one touch to pick.
    private var savedPlacesRow: some View {
        HStack(spacing: 8) {
            ForEach(model.savedPlaces) { place in
                Button {
                    select(place.destination)
                } label: {
                    Label(place.tag.title, systemImage: place.tag.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("\(place.tag.title), \(place.destination.name)")
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            message = trimmed.isEmpty ? "Type a place, a street or a station." : nil
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let near = model.location.currentLocation?.coordinate
        do {
            let found = try await model.routing.search(trimmed, near: near)
            guard !Task.isCancelled else { return }
            results = found
            message = found.isEmpty ? "No places found." : nil
        } catch is CancellationError {
            // Superseded by newer input.
        } catch {
            message = "Search failed. Check your connection."
        }
    }
}

#Preview {
    DestinationSearchView()
        .environment(AppModel.shared)
}
