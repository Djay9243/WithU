//
//  TripRecapView.swift
//  WithU
//
//  The story of one finished trip: where you went, how long it took and the
//  moments you shared, with a card you can share.
//

import MapKit
import SwiftUI

struct TripRecapView: View {
    @Environment(AppModel.self) private var model
    var journey: Journey
    /// Rendered once per change, not on every redraw (rendering is expensive).
    @State private var shareImage: Image?

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
        .task(id: stories.map(\.id)) {
            shareImage = makeShareImage()
        }
        .navigationTitle("Trip Recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let image = shareImage {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: image, preview: SharePreview("My trip to \(journey.destinationName)", image: image)) {
                        Label("Share Recap", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
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
                        StoryPin(story: story)
                    }
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// The shareable card as an image.
    private func makeShareImage() -> Image? {
        let photos = stories.compactMap { $0.photoFiles.first }.prefix(4)
            .compactMap { model.stories.thumbnail(named: $0, maxPixelSize: 800) }
        let card = RecapCard(journey: journey, photos: Array(photos), momentCount: stories.count)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
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
    @Environment(AppModel.self) private var model
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

/// The image that's shared from a recap. Fixed light colours so it looks the
/// same wherever it's posted.
private struct RecapCard: View {
    var journey: Journey
    /// Rendered once per change, not on every redraw (rendering is expensive).
    @State private var shareImage: Image?
    var photos: [UIImage]
    var momentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image("WithULogo")
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("WithU")
                    .font(.headline)
                Spacer()
                Text(journey.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(journey.destinationName)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(2)
            if !photos.isEmpty {
                // A plain Grid: lazy grids don't draw inside ImageRenderer,
                // which left the shared card without its photos.
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: photos.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(start..<min(start + 2, photos.count), id: \.self) { index in
                                Color.clear
                                    .frame(height: photos.count == 1 ? 260 : 150)
                                    .frame(maxWidth: .infinity)
                                    .overlay {
                                        Image(uiImage: photos[index])
                                            .resizable()
                                            .scaledToFill()
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
            HStack(spacing: 18) {
                Label(Format.duration(journey.duration), systemImage: "clock.fill")
                Label(Format.distance(journey.distance), systemImage: journey.mode.symbol)
                Label("\(momentCount)", systemImage: "camera.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.43, green: 0.39, blue: 0.78))
        }
        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.13))
        .padding(22)
        .frame(width: 360)
        .background(Color(red: 0.96, green: 0.94, blue: 0.91))
        .environment(\.colorScheme, .light)
    }
}
