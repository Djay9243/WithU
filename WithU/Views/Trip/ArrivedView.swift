//
//  ArrivedView.swift
//  WithU
//

import SwiftUI

struct ArrivedView: View {
    @Environment(AppModel.self) private var model

    private var trip: TripManager { model.trip }

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.safeGreen.opacity(0.18))
                        .frame(width: 128, height: 128)
                    Circle()
                        .fill(Theme.safeGreen)
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                Text("You've Arrived")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.primary)
                    Text("Trip route is deleted automatically after this trip.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .card(fill: Theme.lavender, padding: 12)
                .padding(.horizontal, 36)

                Spacer()

                Button("Done") {
                    trip.finish()
                }
                .buttonStyle(.primary)
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
            }
        }
    }

    private var summary: String {
        let name = trip.plan?.destination.name ?? "Your destination"
        let start = Format.clock(trip.startedAt)
        let end = Format.clock(trip.arrivedAt ?? .now)
        return "\(name). \(start)–\(end) trip. Your contacts were told you're safe and sharing has stopped."
    }
}

#Preview {
    ArrivedView()
        .environment(AppModel.shared)
}
