//
//  AlertingCircleView.swift
//  WithU
//
//  Your circle has been asked to check on you. Everyone hears at the same
//  time, with the last place your phone was seen and your battery.
//

import SwiftUI

struct AlertingCircleView: View {
    @Environment(AppModel.self) private var model

    private var trip: TripManager { model.trip }

    var body: some View {
        ZStack {
            ScreenBackground(tone: .alert)
            VStack(alignment: .leading, spacing: 16) {
                StatusPill(text: "Alert Sent", tint: Theme.amber)
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alerted \(circleLabel)")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text("They can see your location and battery. Tap I'm Safe if you're okay.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        if let responder = trip.respondingContact {
                            Label("\(responder.name) is on it.", systemImage: "heart.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.deepGreen)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card(fill: Theme.safeGreen.opacity(0.15), padding: 12)
                        }
                        snapshotCard
                        ForEach(trip.alertStates) { state in
                            contactRow(state)
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        Task { await trip.requestCancelAlert() }
                    } label: {
                        Label("I'm Safe", systemImage: model.auth.biometryAvailable ? "faceid" : "lock.fill")
                    }
                    .buttonStyle(.primary(Theme.deepGreen))
                    Text("Tells your circle you're okay.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }

    private var circleLabel: String {
        trip.circleName.isEmpty ? "your circle" : trip.circleName
    }

    private func contactRow(_ state: ContactAlertState) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: state.contact.name, colorIndex: state.contact.colorIndex, size: 40)
            Text(state.contact.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            StatusPill(text: state.status.label, tint: tint(for: state.status), showsDot: false)
        }
        .card(padding: 12)
    }

    /// What the circle received: the last detected place and time, and battery.
    private var snapshotCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.fill.viewfinder")
                .font(.title3)
                .foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("What they see")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let snapshot = trip.lastSnapshot {
                    Label(locationText(snapshot), systemImage: "mappin.and.ellipse")
                    Label(batteryText(snapshot), systemImage: batterySymbol(snapshot.batteryLevel))
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
            Spacer()
        }
        .card(fill: Theme.lavender, padding: 12)
    }

    private func locationText(_ snapshot: LocationSnapshot) -> String {
        guard snapshot.hasLocation else { return "Location not found yet" }
        return String(format: "Last seen %@ · %.4f, %.4f",
                      Format.clock(snapshot.timestamp), snapshot.latitude, snapshot.longitude)
    }

    private func batteryText(_ snapshot: LocationSnapshot) -> String {
        guard let level = snapshot.batteryLevel else { return "Battery unknown" }
        return "Battery \(Int((level * 100).rounded()))%"
    }

    private func batterySymbol(_ level: Double?) -> String {
        guard let level else { return "battery.0percent" }
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func tint(for status: ContactAlertStatus) -> Color {
        switch status {
        case .notYetNotified: Theme.inkSecondary
        case .notified: Theme.amber
        case .delivered: Theme.primary
        case .noResponse: Theme.amber
        case .onIt: Theme.deepGreen
        case .unreachable: Theme.inkSecondary
        }
    }
}

#Preview {
    AlertingCircleView()
        .environment(AppModel.shared)
}
