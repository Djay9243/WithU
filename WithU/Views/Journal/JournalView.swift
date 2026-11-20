//
//  JournalView.swift
//  WithU
//
//  Your travel journal: every story you've shared and every trip you've taken.
//

import SwiftUI

struct JournalView: View {
    @Environment(AppModel.self) private var model
    @State private var composing = false

    private var stories: [Story] { model.stories.stories }
    private var journeys: [Journey] { model.stories.journeys }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    storiesSection
                    tripsSection
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        composing = true
                    } label: {
                        Label("Share a Moment", systemImage: "camera.fill")
                    }
                }
            }
            .storyDestinations()
        }
        .sheet(isPresented: $composing) {
            StoryComposerView()
                .environment(model)
        }
    }

    private var storiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Stories")
            if stories.isEmpty {
                EmptyJournalCard(systemImage: "camera.fill",
                                 title: "No stories yet",
                                 message: "Tap the camera to share a moment.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(stories) { story in
                        NavigationLink(value: story.id) {
                            StoryThumbnail(story: story, size: 104)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Trips")
            if journeys.isEmpty {
                EmptyJournalCard(systemImage: "map.fill",
                                 title: "Your trips will live here",
                                 message: "Finished trips show up here.")
            } else {
                VStack(spacing: 10) {
                    ForEach(journeys) { journey in
                        NavigationLink(value: journey) {
                            JourneyRow(journey: journey,
                                       momentCount: model.stories.stories(forTrip: journey.id).count)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                model.stories.deleteJourney(journey)
                            } label: {
                                Label("Remove Trip", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

struct JourneyRow: View {
    var journey: Journey
    var momentCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: journey.mode.symbol)
                .font(.headline)
                .foregroundStyle(Theme.onTint)
                .frame(width: 44, height: 44)
                .background(journey.mode.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(journey.destinationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(journey.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Format.duration(journey.duration))")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if momentCount > 0 {
                Label("\(momentCount)", systemImage: "camera.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary.opacity(0.6))
        }
        .card(fill: Theme.surface, padding: 12)
    }
}

/// A friendly empty state.
struct EmptyJournalCard: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            SymbolBadge(systemImage: systemImage, size: 56)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(fill: Theme.surface, padding: 20)
    }
}

extension View {
    /// Destinations for story and trip links inside a NavigationStack.
    func storyDestinations() -> some View {
        navigationDestination(for: UUID.self) { id in
            StoryDetailView(storyID: id)
        }
        .navigationDestination(for: Journey.self) { journey in
            TripRecapView(journey: journey)
        }
    }
}

#Preview {
    JournalView()
        .environment(AppModel.shared)
}
