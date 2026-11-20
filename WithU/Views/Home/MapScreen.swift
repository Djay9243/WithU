//
//  MapScreen.swift
//  WithU
//
//  The Map tab: a full-screen map with floating Liquid Glass controls.
//  Pick a place and a short sheet shows the time and Start. A recent place
//  and Start is two touches; Where to?, a place and Start is three.
//

import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Namespace private var glass

    // Planning
    @State private var destination: Destination?
    @State private var route: RouteResult?
    @State private var isPlanning = false
    @State private var errorMessage: String?

    // Presentation
    @State private var showingSearch = false
    @State private var showingSettings = false
    /// Picked in search; applied once the search sheet has closed.
    @State private var pendingDestination: Destination?
    /// Set when Start is tapped; the trip begins once the sheet has closed.
    @State private var startingDestination: Destination?

    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(Italy.region))

    private var mode: TravelMode { model.settings.lastTravelMode }

    /// A little taller when there's a route note (e.g. which stations).
    private var sheetHeight: CGFloat { route?.note == nil ? 300 : 340 }

    private struct PlanKey: Equatable {
        var destination: Destination?
        var mode: TravelMode
    }

    var body: some View {
        ZStack {
            map
            VStack {
                topBar
                Spacer()
                if destination == nil {
                    bottomBar
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .task(id: PlanKey(destination: destination, mode: mode)) {
            await plan()
        }
        .sheet(isPresented: $showingSearch, onDismiss: applyPendingDestination) {
            DestinationSearchView { picked in
                pendingDestination = picked
            }
            .environment(model)
            .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .sheet(isPresented: tripSheetPresented, onDismiss: startIfRequested) {
            TripSheet(destination: destination,
                      route: route,
                      isPlanning: isPlanning,
                      errorMessage: errorMessage,
                      onStart: requestStart)
                .environment(model)
                .presentationDetents([.height(sheetHeight)])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(sheetHeight)))
                .presentationDragIndicator(.visible)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera,
            bounds: MapCameraBounds(centerCoordinateBounds: Italy.region, maximumDistance: 3_000_000)) {
            UserAnnotation()
            if let route {
                RouteLines(legs: route.legs)
            }
            if let destination {
                Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate)
                    .tint(mode.routeColor)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        .mapControlVisibility(.hidden)
        // Keep the route clear of the trip sheet.
        .safeAreaPadding(.bottom, destination == nil ? 0 : sheetHeight)
        .ignoresSafeArea()
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3.weight(.medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Settings")

                    Button {
                        withAnimation(.easeInOut) { camera = .userLocation(fallback: .region(Italy.region)) }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.title3.weight(.medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Center on Me")
                }
            }
            .tint(Theme.ink)
        }
        .padding(.top, 8)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .trailing, spacing: 12) {
                if !model.recentDestinations.isEmpty {
                    recents
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Button {
                        showingSearch = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.primary)
                            Text("Where to?")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                        }
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .frame(height: 58)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("search", in: glass)
                    .accessibilityLabel("Where to?")
                }
            }
        }
    }

    private var recents: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.recentDestinations.prefix(3)) { place in
                    Button {
                        choose(place)
                    } label: {
                        Label(place.name, systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Go to \(place.name)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .transition(.opacity)
    }

    // MARK: Logic

    private var tripSheetPresented: Binding<Bool> {
        Binding(
            get: { destination != nil },
            set: { shown in
                if !shown, startingDestination == nil { clear() }
            }
        )
    }

    private func applyPendingDestination() {
        if let pendingDestination { choose(pendingDestination) }
        pendingDestination = nil
    }

    private func choose(_ place: Destination) {
        model.rememberDestination(place)
        route = nil
        errorMessage = nil
        destination = place
    }

    private func clear() {
        destination = nil
        route = nil
        errorMessage = nil
        withAnimation(.easeInOut) { camera = .userLocation(fallback: .region(Italy.region)) }
    }

    private func plan() async {
        guard let destination else { return }
        isPlanning = true
        errorMessage = nil
        defer { isPlanning = false }
        do {
            route = try await model.planRoute(to: destination, mode: mode)
            withAnimation(.easeInOut) { camera = .automatic }
        } catch is CancellationError {
            // A newer plan replaced this one.
        } catch {
            route = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Closes the sheet first; the trip screen opens once it's gone.
    private func requestStart() {
        startingDestination = destination
        destination = nil
    }

    private func startIfRequested() {
        guard let place = startingDestination else { return }
        startingDestination = nil
        guard let route else { return }
        let plan = model.makePlan(destination: place,
                                  mode: mode,
                                  route: route,
                                  deadlineEnabled: model.settings.homeDeadlineEnabled)
        do {
            try model.startTrip(plan: plan, route: route)
            self.route = nil
        } catch {
            errorMessage = error.localizedDescription
            destination = place
        }
    }
}

// MARK: - Trip sheet

/// The short sheet shown for a chosen place: time, who it's shared with, Start.
private struct TripSheet: View {
    @Environment(AppModel.self) private var model
    var destination: Destination?
    var route: RouteResult?
    var isPlanning: Bool
    var errorMessage: String?
    var onStart: () -> Void

    private var mode: TravelMode { model.settings.lastTravelMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(destination?.name ?? "")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let subtitle = destination?.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                if isPlanning {
                    ProgressView()
                } else if let route {
                    Text(Format.duration(route.expectedTravelTime))
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text(Format.distance(route.distance))
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.alertRed)
                        .lineLimit(2)
                }
                Spacer()
                modeRow
            }

            if let note = route?.note, !isPlanning {
                HStack(spacing: 8) {
                    Image(systemName: mode == .transit ? "tram.fill" : "info.circle")
                        .foregroundStyle(mode.routeColor)
                    Text(note)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    if mode == .transit, let destination {
                        // Exact lines and changes come from Apple Maps.
                        Button("Lines in Maps") { openTransitInMaps(destination) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            }

            CirclePickerRow()

            Button(action: onStart) {
                Label(startTitle, systemImage: "location.fill")
            }
            .buttonStyle(.primary)
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var canStart: Bool { route != nil && !isPlanning && !model.contacts.isEmpty }

    private func openTransitInMaps(_ destination: Destination) {
        let item = MKMapItem(location: destination.location, address: nil)
        item.name = destination.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
    }

    private var startTitle: String {
        model.contacts.isEmpty ? "Add People in Circle" : "Start"
    }

    /// Compact switch between the four travel modes.
    private var modeRow: some View {
        HStack(spacing: 6) {
            ForEach(TravelMode.allCases) { option in
                let selected = option == mode
                Button {
                    model.settings.lastTravelMode = option
                } label: {
                    Image(systemName: option.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Theme.onTint : Theme.inkSecondary)
                        .frame(width: 38, height: 38)
                        .background(selected ? option.tint : Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Gentle press feedback for cards and buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    MainTabView()
        .environment(AppModel.shared)
}
