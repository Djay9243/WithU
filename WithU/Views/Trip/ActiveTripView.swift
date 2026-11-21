//
//  ActiveTripView.swift
//  WithU
//
//  The running trip: map with the route, the countdown, and the actions you
//  need on the way.
//

import MapKit
import SwiftUI

struct ActiveTripView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmingEnd = false
    @State private var composing = false
    @State private var showingMoments = false
    @State private var confirmingArrival = false
    @State private var openedStory: Story?
    /// The story that was just saved, for the short "Moment saved" note.
    @State private var savedStoryID: UUID?

    private var trip: TripManager { model.trip }
    private var mode: TravelMode { trip.plan?.mode ?? .walk }

    var body: some View {
        VStack(spacing: 0) {
            map
            panel
        }
        .background(Theme.cream)
        .alert("End This Trip?", isPresented: $confirmingEnd) {
            Button("Keep Going", role: .cancel) {}
            Button("End Trip", role: .destructive) {
                Task { _ = await trip.cancelTrip() }
            }
        } message: {
            Text("Location sharing stops and \(trip.circleName) is told the trip was cancelled.")
        }
        .sheet(isPresented: $composing) {
            StoryComposerView { story in
                savedStoryID = story.id
            }
            .environment(model)
            .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .sheet(isPresented: $showingMoments) {
            TripMomentsSheet(tripID: trip.tripID)
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .sheet(item: $openedStory) { story in
            NavigationStack {
                StoryDetailView(storyID: story.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { openedStory = nil }
                        }
                    }
            }
            .environment(model)
            .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .task(id: savedStoryID) {
            guard savedStoryID != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { savedStoryID = nil }
        }
    }

    private var moments: [Story] { model.stories.stories(forTrip: trip.tripID) }
    private var momentCount: Int { moments.count }
    /// Photos with a place get a pin on the map.
    private var pinnedMoments: [Story] { moments.filter { $0.mapCoordinate != nil } }

    // MARK: Map

    private var map: some View {
        // The map runs under the status bar; the buttons stay inside the safe area.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Map(position: $camera) {
                    UserAnnotation()
                    RouteLines(legs: trip.routeLegs)
                    if let plan = trip.plan {
                        Marker(plan.destination.name, systemImage: "flag.checkered", coordinate: plan.destination.coordinate)
                            .tint(mode.routeColor)
                    }
                    // A round photo where each moment was taken.
                    ForEach(pinnedMoments) { story in
                        if let coordinate = story.mapCoordinate {
                            Annotation("", coordinate: coordinate, anchor: .center) {
                                Button {
                                    openedStory = story
                                } label: {
                                    // Map annotations don't inherit AppModel; pass it in.
                                    StoryRoundPhoto(story: story, size: 40, borderWidth: 3)
                                        .environment(model)
                                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(story.caption.isEmpty ? "Moment from this trip" : "Moment: \(story.caption)")
                            }
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .including([.publicTransport, .cafe, .store, .restaurant, .pharmacy])))
                .mapControlVisibility(.hidden)
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        // The photos taken on this trip: the newest one and the count.
                        if let latest = moments.first {
                            Button {
                                showingMoments = true
                            } label: {
                                HStack(spacing: 6) {
                                    StoryRoundPhoto(story: latest, size: 30)
                                    Text("\(momentCount)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                .padding(.leading, 7)
                                .padding(.trailing, 12)
                                .frame(height: 44)
                                .background(Theme.surface, in: Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("See \(momentCount) \(momentCount == 1 ? "moment" : "moments") from this trip")
                        }

                        Spacer()

                        Button {
                            Task { await centerOnUser() }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 44, height: 44)
                                .background(Theme.surface, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Center on Me")
                    }
                    if trip.waitingForSignal {
                        StatusPill(text: "No signal. We'll wait with you.", tint: Theme.amber)
                    }
                    if savedStoryID != nil {
                        Label("Moment saved", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.surface, in: Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .animation(.snappy, value: savedStoryID)
            }
            .overlay(alignment: .bottom) {
                // Floats on the map, right above the trip panel.
                Button {
                    composing = true
                } label: {
                    Label("Share a Moment", systemImage: "camera.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 24)
                        .frame(height: 54)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // See-through Liquid Glass with a hint of the app's purple; it
                // bends the map behind it and reacts when pressed.
                .glassEffect(.regular.tint(Theme.primary.opacity(0.18)).interactive(), in: .capsule)
                .padding(.bottom, 16)
            }
    }

    /// Moves the map to where you are, from the trip's live location.
    private func centerOnUser() async {
        let fix = await model.location.currentFix()
        withAnimation(.easeInOut) {
            if let fix {
                camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 800))
            } else {
                camera = .userLocation(fallback: .automatic)
            }
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 14) {
            timerCard
            // Face ID first, so nobody else can end the safety by saying you arrived.
            Button {
                guard !confirmingArrival else { return }
                confirmingArrival = true
                Task {
                    await trip.confirmArrival()
                    confirmingArrival = false
                }
            } label: {
                Label("I've Arrived", systemImage: model.auth.biometryAvailable ? "faceid" : "checkmark.shield.fill")
            }
            .buttonStyle(.primary(Theme.safeGreen))
            .disabled(confirmingArrival)

            Button {
                confirmingEnd = true
            } label: {
                Label("End Trip", systemImage: "xmark")
            }
            .buttonStyle(.secondary(Theme.inkSecondary))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Theme.cream)
    }

    private var timerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: mode.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onTint)
                    .frame(width: 32, height: 32)
                    .background(mode.tint, in: Circle())
                    .accessibilityLabel(mode.title)
                Text(trip.plan?.destination.name ?? "Destination")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
            }

            // Public transport: where to get on and where to get off.
            if trip.routeLegs.contains(where: { $0.kind == .ride }) {
                TransitSteps(legs: trip.routeLegs,
                             destinationName: trip.plan?.destination.name ?? "your destination",
                             compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(timerInterval: trip.startedAt...max(trip.endsAt, trip.startedAt.addingTimeInterval(1)),
                 countsDown: true,
                 showsHours: trip.endsAt.timeIntervalSince(trip.startedAt) >= 3600)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                ProgressView(value: progress(at: context.date))
                    .tint(mode.routeColor)
            }

            HStack {
                HStack(spacing: -8) {
                    ForEach(trip.contacts.prefix(3)) { contact in
                        AvatarView(name: contact.name, colorIndex: contact.colorIndex, size: 24)
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                Text("Sharing with \(trip.circleName)")
                    .lineLimit(1)
                Spacer()
                if let remaining = trip.remainingDistance {
                    Text(Format.distance(remaining))
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
        }
        .card(fill: Theme.surface)
    }

    private func progress(at date: Date) -> Double {
        let total = trip.endsAt.timeIntervalSince(trip.startedAt)
        guard total > 0 else { return 1 }
        let elapsed = date.timeIntervalSince(trip.startedAt)
        return min(max(elapsed / total, 0), 1)
    }
}

#Preview {
    ActiveTripView()
        .environment(AppModel.shared)
}
