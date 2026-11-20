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
    }

    // MARK: Map

    private var map: some View {
        // The map runs under the status bar; the buttons stay inside the safe area.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Map(position: $camera) {
                    UserAnnotation()
                    if !trip.routeCoordinates.isEmpty {
                        MapPolyline(coordinates: trip.routeCoordinates)
                            .stroke(mode.routeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                    if let plan = trip.plan {
                        Marker(plan.destination.name, systemImage: "flag.checkered", coordinate: plan.destination.coordinate)
                            .tint(mode.routeColor)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .including([.publicTransport, .cafe, .store, .restaurant, .pharmacy])))
                .mapControlVisibility(.hidden)
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    HStack {
                        Spacer()

                        Button {
                            withAnimation(.easeInOut) { camera = .userLocation(fallback: .automatic) }
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 14) {
            timerCard
            Button {
                trip.arrive()
            } label: {
                Label("I've Arrived", systemImage: "checkmark.shield.fill")
            }
            .buttonStyle(.primary(Theme.safeGreen))

            HStack(spacing: 12) {
                Button {
                    confirmingEnd = true
                } label: {
                    Label("End Trip", systemImage: "xmark")
                }
                .buttonStyle(.secondary(Theme.inkSecondary))

                Button {
                    trip.emergency()
                } label: {
                    Label("SOS", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.secondary(Theme.alertRed))
            }
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
