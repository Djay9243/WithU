//
//  DestinationSearchView.swift
//  WithU
//
//  Apple Maps place and address search, biased to where the person is.
//

import SwiftUI

struct DestinationSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onSelect: (Destination) -> Void

    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var isSearching = false
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.inkSecondary)
                        TextField("Search for a place or address", text: $query)
                            .focused($focused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .foregroundStyle(Theme.ink)
                        if isSearching {
                            ProgressView()
                        } else if !query.isEmpty {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if let message, !showsRecents {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.top, 24)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if showsRecents {
                                SectionLabel(text: "Recents")
                                    .padding(.top, 8)
                            }
                            ForEach(showsRecents ? model.recentDestinations : results) { destination in
                                Button {
                                    onSelect(destination)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: showsRecents ? "clock.arrow.circlepath" : "mappin.circle.fill")
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
                }
            }
            .navigationTitle("Where To?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Back")
                }
            }
            .keyboardDismissible()
        }
        .onAppear { focused = true }
        .task(id: query) {
            await search()
        }
    }

    /// Recent places are shown until the person starts typing.
    private var showsRecents: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && !model.recentDestinations.isEmpty
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
    DestinationSearchView { _ in }
        .environment(AppModel.shared)
}
