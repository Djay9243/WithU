//
//  AlertingCircleView.swift
//  WithU
//
//  The escalation chain in progress: contact #1 first, then everyone.
//

import SwiftUI

struct AlertingCircleView: View {
    @Environment(AppModel.self) private var model

    private var trip: TripManager { model.trip }

    var body: some View {
        ZStack {
            ScreenBackground(tone: .alert)
            VStack(alignment: .leading, spacing: 16) {
                StatusPill(text: "Alert Active", tint: Theme.alertRed)
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alerting Your Circle")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text("Telling \(trip.circleName), one by one.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(trip.alertStates) { state in
                            contactRow(state)
                        }
                        snapshotCard
                        if let responder = trip.respondingContact {
                            Label("\(responder.name) is on it.", systemImage: "checkmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.deepGreen)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card(fill: Theme.safeGreen.opacity(0.15), padding: 12)
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
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }

    private func contactRow(_ state: ContactAlertState) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: state.contact.name, colorIndex: state.contact.colorIndex, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.contact.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            StatusPill(text: state.status.label, tint: tint(for: state.status), showsDot: false)
        }
        .card(padding: 12)
    }

    private var snapshotCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill.viewfinder")
                .font(.title3)
                .foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Location and battery shared")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let snapshot = trip.lastSnapshot {
                    Text(String(format: "%.4f, %.4f · %d%% battery · %@",
                                snapshot.latitude, snapshot.longitude,
                                Int(snapshot.batteryLevel * 100),
                                Format.clock(snapshot.timestamp)))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
        }
        .card(fill: Theme.lavender, padding: 12)
    }

    private func tint(for status: ContactAlertStatus) -> Color {
        switch status {
        case .notYetNotified: Theme.inkSecondary
        case .notified: Theme.amber
        case .delivered: Theme.primary
        case .noResponse: Theme.alertRed
        case .onIt: Theme.deepGreen
        case .unreachable: Theme.inkSecondary
        }
    }
}

#Preview {
    AlertingCircleView()
        .environment(AppModel.shared)
}
