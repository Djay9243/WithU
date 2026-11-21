//
//  TripRecapView.swift
//  WithU
//
//  The story of one finished trip: where you went, how long it took and the
//  moments you shared.
//

import MapKit
import SwiftUI

struct TripRecapView: View {
    @Environment(AppModel.self) private var model
    var journey: Journey

    private var stories: [Story] { model.stories.stories(forTrip: journey.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stats
                if !pinned.isEmpty { momentsMap }
                if stories.isEmpty {
                    Text("No moments were shared on this trip.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .card(fill: Theme.surface)
                } else {
                    SectionLabel(text: "Moments")
                    LazyVGrid(columns: StoryGrid.columns, spacing: 10) {
                        ForEach(stories) { story in
                            NavigationLink(value: story.id) {
                                StoryThumbnail(story: story, size: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(ScreenBackground())
        .navigationTitle("Trip Recap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pinned: [Story] { stories.filter { $0.mapCoordinate != nil } }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(journey.startedAt.formatted(date: .complete, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(journey.destinationName)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            RecapStat(value: Format.duration(journey.duration), label: "Time", systemImage: "clock.fill")
            RecapStat(value: Format.distance(journey.distance), label: journey.mode.title, systemImage: journey.mode.symbol)
            RecapStat(value: "\(stories.count)", label: stories.count == 1 ? "Moment" : "Moments", systemImage: "camera.fill")
        }
    }

    private var momentsMap: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(pinned) { story in
                if let coordinate = story.mapCoordinate {
                    Annotation(story.displayPlace ?? "", coordinate: coordinate) {
                        // Map annotations don't inherit custom environment
                        // objects, so StoryPhoto would crash looking for AppModel.
                        StoryPin(story: story)
                            .environment(model)
                    }
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RecapStat: View {
    var value: String
    var label: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primary)
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Theme.surface, padding: 14)
    }
}

/// A story's photo as a round map pin.
private struct StoryPin: View {
    var story: Story

    var body: some View {
        Group {
            if let file = story.photoFiles.first {
                StoryPhoto(file: file, maxPixelSize: 150)
            } else {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.primary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}
