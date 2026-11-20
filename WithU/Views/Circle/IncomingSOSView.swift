//
//  IncomingSOSView.swift
//  WithU
//
//  What someone in your circle sees when you need help: where you are, how
//  much battery you have, and one tap to say they're on it, call or get
//  directions.
//

import MapKit
import SwiftUI
import UIKit

struct IncomingSOSView: View {
    var trip: FollowedTrip
    var hasResponded: Bool
    var onOnIt: () -> Void
    var onClose: () -> Void

    @State private var camera: MapCameraPosition
    @State private var pulse = false

    init(trip: FollowedTrip, hasResponded: Bool, onOnIt: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.trip = trip
        self.hasResponded = hasResponded
        self.onOnIt = onOnIt
        self.onClose = onClose
        if let coordinate = trip.coordinate {
            _camera = State(initialValue: .region(MKCoordinateRegion(center: coordinate,
                                                                    latitudinalMeters: 800,
                                                                    longitudinalMeters: 800)))
        } else {
            _camera = State(initialValue: .automatic)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            map
            details
        }
        .background(Theme.cream)
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            pulse = true
        }
    }

    // MARK: Map

    private var map: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Map(position: $camera) {
                    if let coordinate = trip.coordinate {
                        Annotation(trip.name, coordinate: coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Theme.alertRed.opacity(0.25))
                                    .frame(width: 90, height: 90)
                                    .scaleEffect(pulse ? 1.15 : 0.7)
                                    .opacity(pulse ? 0.2 : 0.8)
                                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
                                AvatarView(name: trip.name, colorIndex: 1, size: 48)
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                            }
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .including([.publicTransport, .hospital, .police, .pharmacy])))
                .mapControlVisibility(.hidden)
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 12)
                .accessibilityLabel("Close")
                .accessibilityHint("You can open this again from Circles.")
            }
            .overlay {
                if trip.coordinate == nil {
                    Label("Location not shared yet", systemImage: "location.slash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: Capsule())
                }
            }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(text: "Check on \(trip.name)", tint: Theme.amber)
                    Text("\(trip.name) hasn't checked in")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text("Sent \(trip.stateSince.formatted(.relative(presentation: .named)))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                if let battery = trip.battery {
                    infoTile(title: "Battery",
                             value: "\(Int((battery * 100).rounded()))%",
                             systemImage: batterySymbol(battery),
                             tint: battery <= 0.2 ? Theme.alertRed : Theme.safeGreen)
                }
                infoTile(title: "Last Seen",
                         value: (trip.lastSeen ?? trip.updatedAt).formatted(date: .omitted, time: .shortened),
                         systemImage: "clock.fill",
                         tint: Theme.primary)
            }

            if let destination = trip.destination {
                Label("Was heading to \(destination)", systemImage: "flag.checkered")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
            }

            Button {
                onOnIt()
            } label: {
                Label(hasResponded ? "\(trip.name) Knows You're On It" : "I'm On It",
                      systemImage: hasResponded ? "checkmark" : "hand.raised.fill")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.primary(hasResponded ? Theme.deepGreen : Theme.alertRed))
            .disabled(hasResponded)

            HStack(spacing: 12) {
                if let phone = trip.phone, let url = Self.callURL(phone) {
                    Link(destination: url) {
                        Label("Call", systemImage: "phone.fill")
                    }
                    .buttonStyle(.secondary(Theme.ink))
                }
                if trip.coordinate != nil {
                    Button {
                        openDirections()
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.secondary(Theme.ink))
                }
            }

            Text("Try calling \(trip.name) first. If you can't reach them and you're worried, call 112.")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func infoTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .card(fill: Theme.surface, padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func batterySymbol(_ level: Double) -> String {
        switch level {
        case ..<0.13: "battery.0percent"
        case ..<0.38: "battery.25percent"
        case ..<0.63: "battery.50percent"
        case ..<0.88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private func openDirections() {
        guard let coordinate = trip.coordinate else { return }
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                             address: nil)
        item.name = trip.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    static func callURL(_ phone: String) -> URL? {
        let dialable = phone.filter { $0.isNumber || $0 == "+" }
        return dialable.isEmpty ? nil : URL(string: "tel:\(dialable)")
    }
}

extension FollowedTrip {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude, latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview("Incoming Alert") {
    IncomingSOSView(trip: FollowedTrip(fromUser: "a",
                                       name: "Sara",
                                       destination: "Napoli Piazza Garibaldi",
                                       state: .needsHelp,
                                       endsAt: .now.addingTimeInterval(600),
                                       latitude: 40.8530,
                                       longitude: 14.2681,
                                       battery: 0.18,
                                       updatedAt: .now.addingTimeInterval(-20),
                                       stateSince: .now.addingTimeInterval(-45),
                                       phone: "+39 333 123 4567"),
                    hasResponded: false,
                    onOnIt: {},
                    onClose: {})
}
