//
//  HomeView.swift
//  WithU
//
//  The Map tab: you, your planned route, and a sliding panel to plan and
//  start a trip.
//

import MapKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    // Trip planning
    @State private var destination: Destination?
    @State private var mode: TravelMode = .walk
    @State private var route: RouteResult?
    @State private var isPlanning = false
    @State private var errorMessage: String?
    @State private var didLoadMode = false

    // Presentation
    @State private var showingSearch = false
    @State private var panelExpanded = false

    // Map
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var satellite = false

    private struct PlanKey: Equatable {
        var destination: Destination?
        var mode: TravelMode
    }

    private let stopOptions = [5, 8, 12, 15, 20]

    /// How much of the panel shows when it's collapsed.
    private var collapsedPanelHeight: CGFloat {
        model.recentDestinations.isEmpty || destination != nil ? 360 : 410
    }

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            map
                // Centre the map in the area above the panel, not behind it.
                .safeAreaPadding(.top, 60)
                .safeAreaPadding(.bottom, collapsedPanelHeight + 40)
                .ignoresSafeArea()

            BottomPanel(isExpanded: $panelExpanded,
                        collapsedHeight: collapsedPanelHeight,
                        model: model) {
                mapButtons
            } content: {
                PanelSurface(isExpanded: $panelExpanded) {
                    panelContent(settings: $model.settings)
                }
            }
        }
        .onAppear {
            if !didLoadMode {
                mode = model.settings.lastTravelMode
                didLoadMode = true
            }
        }
        .task(id: PlanKey(destination: destination, mode: mode)) {
            await plan()
        }
        .sheet(isPresented: $showingSearch) {
            DestinationSearchView { picked in
                choose(picked)
            }
            .environment(model)
            .preferredColorScheme(model.settings.appearance.colorScheme)
        }
    }

    // MARK: - Map

    /// The route and destination of the running trip, or of the one being planned.
    private var shownRoute: (coordinates: [CLLocationCoordinate2D], destination: Destination?, mode: TravelMode) {
        if model.trip.isActive, let plan = model.trip.plan {
            return (model.trip.routeCoordinates, plan.destination, plan.mode)
        }
        return (route?.coordinates ?? [], destination, mode)
    }

    private var map: some View {
        let shown = shownRoute
        return Map(position: $camera) {
            UserAnnotation(anchor: .bottom) {
                UserPin(name: model.settings.userName.isEmpty ? "Me" : model.settings.userName)
            }
            if !shown.coordinates.isEmpty {
                MapPolyline(coordinates: shown.coordinates)
                    .stroke(shown.mode.routeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let place = shown.destination {
                Marker(place.name, systemImage: "flag.checkered", coordinate: place.coordinate)
                    .tint(shown.mode.routeColor)
            }
        }
        .mapStyle(satellite
                  ? .hybrid(elevation: .flat, pointsOfInterest: .all)
                  : .standard(elevation: .flat, pointsOfInterest: .all))
        .mapControlVisibility(.hidden)
    }

    private var mapButtons: some View {
        VStack(spacing: 12) {
            RoundIconButton(systemImage: "location.fill", label: "Center on Me") {
                withAnimation(.easeInOut) { camera = .userLocation(fallback: .automatic) }
            }
            RoundIconButton(systemImage: satellite ? "map.fill" : "globe.europe.africa.fill",
                            label: satellite ? "Standard Map" : "Satellite Map") {
                satellite.toggle()
            }
        }
    }

    // MARK: - Panel content

    @ViewBuilder
    private func panelContent(settings: Binding<AppSettings>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            destinationField
            if destination != nil {
                estimateRow
                startButton
            } else if !model.recentDestinations.isEmpty {
                recentsRow
            }
            modeRow
            shareWithSection
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.alertRed)
            }
            checkInRules(settings: settings)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var destinationField: some View {
        HStack(spacing: 10) {
            Button {
                showingSearch = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(destination?.name ?? "Where to?")
                            .font(.body.weight(destination == nil ? .regular : .semibold))
                            .foregroundStyle(destination == nil ? Theme.inkSecondary : Theme.ink)
                            .lineLimit(1)
                        if let subtitle = destination?.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if destination != nil {
                Button {
                    destination = nil
                    route = nil
                    withAnimation(.easeInOut) { camera = .userLocation(fallback: .automatic) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Destination")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The last three places you searched for, one tap to pick again.
    private var recentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.recentDestinations) { place in
                    Button {
                        choose(place)
                    } label: {
                        Label(place.name, systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recent: \(place.name)")
                }
            }
        }
    }

    private var modeRow: some View {
        HStack(spacing: 10) {
            ForEach(TravelMode.allCases) { option in
                let selected = mode == option
                Button {
                    mode = option
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.symbol)
                            .font(.title3)
                        Text(option.title)
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(selected ? option.tint : Theme.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(selected ? Theme.onTint : Theme.ink)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(option.tint, lineWidth: selected ? 0 : 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var estimateRow: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.symbol)
                .foregroundStyle(Theme.onTint)
                .frame(width: 36, height: 36)
                .background(mode.tint, in: Circle())
            if isPlanning {
                ProgressView()
                Spacer()
            } else if let route {
                Text(Format.duration(route.expectedTravelTime))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                Text(Format.distance(route.distance))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                if route.isBusyRoute {
                    StatusPill(text: "Busy Route", tint: Theme.primary, showsDot: false)
                }
            } else {
                Text("No route found")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
            }
        }
    }

    private var startButton: some View {
        let blocked = route == nil || isPlanning || model.contacts.isEmpty
        return Button {
            start()
        } label: {
            Label("Start Trip", systemImage: "location.fill")
        }
        .buttonStyle(.primary)
        .disabled(blocked)
        .opacity(blocked ? 0.5 : 1)
    }

    private var shareWithSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Share With")
            CirclePickerRow()
            if model.contacts.isEmpty {
                Text("Add people to \(model.selectedCircle.name) in Circles to start a trip.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func checkInRules(settings: Binding<AppSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Check-Ins")
            VStack(spacing: 12) {
                HStack {
                    Text("If I stop for")
                    Menu {
                        Picker("Stop Length", selection: settings.stopThresholdMinutes) {
                            ForEach(stopOptions, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                    } label: {
                        Text("\(settings.wrappedValue.stopThresholdMinutes) min")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.primary)
                    }
                    Spacer()
                    Toggle("If I stop", isOn: settings.checkOnStop)
                        .labelsHidden()
                        .tint(Theme.safeGreen)
                }
                Divider()
                HStack {
                    Text("If I'm not home by")
                    DatePicker("Home By", selection: deadlineBinding(settings), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                    Toggle("If I'm not home by", isOn: settings.homeDeadlineEnabled)
                        .labelsHidden()
                        .tint(Theme.safeGreen)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .card(fill: Theme.surface, padding: 14)
        }
    }

    // MARK: - Logic

    private func deadlineBinding(_ settings: Binding<AppSettings>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = settings.wrappedValue.homeDeadlineMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.wrappedValue.homeDeadlineMinutes = (components.hour ?? 22) * 60 + (components.minute ?? 45)
            }
        )
    }

    private func choose(_ place: Destination) {
        model.rememberDestination(place)
        destination = place
        panelExpanded = true
    }

    private func plan() async {
        guard let destination else {
            route = nil
            return
        }
        isPlanning = true
        errorMessage = nil
        defer { isPlanning = false }
        do {
            route = try await model.planRoute(to: destination, mode: mode)
            // Frame you, the route and the destination.
            withAnimation(.easeInOut) { camera = .automatic }
        } catch is CancellationError {
            // A newer plan superseded this one.
        } catch {
            route = nil
            errorMessage = error.localizedDescription
        }
    }

    private func start() {
        guard let destination, let route else { return }
        let plan = model.makePlan(destination: destination,
                                  mode: mode,
                                  route: route,
                                  deadlineEnabled: model.settings.homeDeadlineEnabled)
        do {
            try model.startTrip(plan: plan, route: route)
            errorMessage = nil
            self.destination = nil
            self.route = nil
            panelExpanded = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Panel surface

/// What the sliding panel shows: handle, scrolling content and background.
/// Movement is handled by `BottomPanel` in UIKit.
private struct PanelSurface<Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.inkSecondary.opacity(0.4))
                .frame(width: 38, height: 5)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
                .accessibilityElement()
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isExpanded.toggle() }

            ScrollView {
                content()
                    .padding(.bottom, 120)
            }
            .scrollDisabled(!isExpanded)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Pulling down past the top of the list closes the panel, like Maps.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                if isExpanded, offset < -60 { isExpanded = false }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Theme.cream)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .stroke(Theme.inkSecondary.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Components

/// Circular floating button used on the map.
private struct RoundIconButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 50, height: 50)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.inkSecondary.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Your avatar pin on the map.
private struct UserPin: View {
    var name: String

    var body: some View {
        VStack(spacing: -6) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white)
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                AvatarView(name: name, colorIndex: 0, size: 48)
            }
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Your Location")
    }
}

#Preview {
    MainTabView()
        .environment(AppModel.shared)
}
