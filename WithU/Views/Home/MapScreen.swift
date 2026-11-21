//
//  MapScreen.swift
//  WithU
//
//  The Map tab: a full-screen map with floating Liquid Glass controls.
//  Pick a place (tap it on the map, or find it in the Search tab) and a
//  short sheet shows the time and Start.
//

import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    // Planning
    @State private var destination: Destination?
    @State private var route: RouteResult?
    @State private var isPlanning = false
    @State private var errorMessage: String?

    // Presentation
    /// A place tapped on the map (a café, a station...).
    @State private var selectedFeature: MapFeature?
    /// When a place was last tapped, so the same tap isn't also read as a
    /// tap on an empty spot.
    @State private var featureTappedAt = Date.distantPast
    /// Set when Start is tapped; the trip begins once the sheet has closed.
    @State private var startingDestination: Destination?
    @State private var showingSettings = false

    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(Italy.region))

    private var mode: TravelMode { model.settings.lastTravelMode }

    /// Taller for public transport steps, a little taller for a route note.
    private var sheetHeight: CGFloat {
        // Includes room for the Close button.
        guard let route else { return 310 }
        if route.legs.contains(where: { $0.kind == .ride }) { return 410 }
        return route.note == nil ? 310 : 350
    }

    private struct PlanKey: Equatable {
        var destination: Destination?
        var mode: TravelMode
    }

    var body: some View {
        ZStack {
            // MapKit keeps tracking you for the blue dot even after the app
            // is closed (the app has the location background mode for trips),
            // which left the location arrow in the Dynamic Island. Removing
            // the map while in the background stops that; it comes back, at
            // the same camera position, when the app is opened again.
            if scenePhase == .background {
                Theme.cream.ignoresSafeArea()
            } else {
                map
            }
            VStack {
                topBar
                    .padding(.horizontal, 16)
                Spacer()
            }
        }
        .task(id: PlanKey(destination: destination, mode: mode)) {
            await plan()
        }
        .onChange(of: selectedFeature) { _, feature in
            guard let feature else { return }
            featureTappedAt = .now
            choose(Destination(name: feature.title ?? "Dropped Pin",
                               subtitle: "",
                               latitude: feature.coordinate.latitude,
                               longitude: feature.coordinate.longitude))
            selectedFeature = nil
        }
        .onChange(of: model.placeToShowOnMap, initial: true) { _, place in
            // A place picked in the Search tab.
            guard let place else { return }
            model.placeToShowOnMap = nil
            choose(place)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .sheet(isPresented: tripSheetPresented, onDismiss: startIfRequested) {
            TripSheet(destination: destination,
                      route: route,
                      isPlanning: isPlanning,
                      errorMessage: errorMessage,
                      onStart: requestStart,
                      onClose: clear)
                .environment(model)
                .presentationDetents([.height(sheetHeight)])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(sheetHeight)))
                .presentationDragIndicator(.visible)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera,
                bounds: MapCameraBounds(centerCoordinateBounds: Italy.region, maximumDistance: 3_000_000),
                selection: $selectedFeature) {
                UserAnnotation()
                if let route {
                    RouteLines(legs: route.legs)
                }
                if let destination {
                    Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate)
                        .tint(mode.routeColor)
                }
            }
            // Tapping an empty spot picks it as the destination.
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                Task { await chooseTappedSpot(coordinate) }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        // Only places (cafés, stations...) can be picked, not city or road names.
        .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
        .mapControlVisibility(.hidden)
        // The app's purple tint would otherwise colour your location dot;
        // keep it the familiar Maps blue.
        .tint(.blue)
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
                        Task { await centerOnUser() }
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

    // MARK: Logic

    private var tripSheetPresented: Binding<Bool> {
        Binding(
            get: { destination != nil },
            set: { shown in
                if !shown, startingDestination == nil { clear() }
            }
        )
    }

    private func choose(_ place: Destination) {
        model.rememberDestination(place)
        route = nil
        errorMessage = nil
        destination = place
    }

    /// A tap on an empty spot: names it from its address, then picks it.
    private func chooseTappedSpot(_ coordinate: CLLocationCoordinate2D) async {
        // Let a tap on a named place win; it arrives as a selection instead.
        try? await Task.sleep(for: .milliseconds(150))
        guard Date.now.timeIntervalSince(featureTappedAt) > 0.5 else { return }
        choose(await PlaceService.destination(at: coordinate))
    }

    /// Moves the map to where you are. Uses a real fix, because setting
    /// `.userLocation` again is a no-op when the camera already holds that value.
    private func centerOnUser() async {
        let fix = await model.location.currentFix()
        withAnimation(.easeInOut) {
            if let fix {
                camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 1500))
            } else {
                camera = .userLocation(fallback: .region(Italy.region))
            }
        }
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
                                  deadlineEnabled: false)
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
    /// Back to the map without starting, from the top-left button.
    var onClose: () -> Void

    private var mode: TravelMode { model.settings.lastTravelMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
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
                Spacer(minLength: 0)
                if let destination {
                    PlaceTagMenu(destination: destination)
                }
                // Top right, like Apple Maps.
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(Theme.ink)
                .accessibilityLabel("Close")
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

            if let route, !isPlanning, let destination,
               route.legs.contains(where: { $0.kind == .ride }) {
                // Public transport: which station to walk to, where to get off.
                HStack(alignment: .top, spacing: 8) {
                    TransitSteps(legs: route.legs, destinationName: destination.name)
                    Spacer(minLength: 4)
                    // Exact lines and changes come from Apple Maps.
                    Button("Lines in Maps") { openTransitInMaps(destination) }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            } else if let note = route?.note, !isPlanning {
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

/// A small tag button on the trip sheet: mark the place as Home, Work or Gym.
private struct PlaceTagMenu: View {
    @Environment(AppModel.self) private var model
    var destination: Destination

    var body: some View {
        let current = model.tag(for: destination)
        Menu {
            ForEach(PlaceTag.allCases) { tag in
                Button {
                    model.setTag(current == tag ? nil : tag, for: destination)
                } label: {
                    Label(tag.title, systemImage: current == tag ? "checkmark" : tag.symbol)
                }
            }
            if current != nil {
                Divider()
                Button(role: .destructive) {
                    model.setTag(nil, for: destination)
                } label: {
                    Label("Remove Tag", systemImage: "tag.slash")
                }
            }
        } label: {
            Image(systemName: current?.symbol ?? "tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(current == nil ? Theme.inkSecondary : Theme.primary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(current.map { "Tagged \($0.title)" } ?? "Tag This Place")
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
