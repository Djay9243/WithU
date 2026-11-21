//
//  SmartCheckInView.swift
//  WithU
//
//  A friendly "Everything okay?". No reply within the window (15 or 20 min)
//  lets the whole circle know, with your last location and battery.
//

import SwiftUI

struct SmartCheckInView: View {
    @Environment(AppModel.self) private var model
    var reason: CheckInReason
    @State private var confirmingHelp = false

    private var trip: TripManager { model.trip }

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 20) {
                StatusPill(text: "Quick Check-In", tint: Theme.primary)
                    .padding(.top, 12)
                Spacer()
                countdownRing
                VStack(spacing: 8) {
                    Text("Everything Okay?")
                        .font(.title.bold())
                        .foregroundStyle(Theme.ink)
                    Text(reason.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(reason.message)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button("I'm Fine") {
                        trip.respondOK()
                    }
                    .buttonStyle(.primary(Theme.deepGreen))
                    Button {
                        trip.respondAddingTime()
                    } label: {
                        Label("Add 10 Min", systemImage: "plus")
                    }
                    .buttonStyle(.secondary(Theme.ink))
                    Button {
                        confirmingHelp = true
                    } label: {
                        Label("I Need Help", systemImage: "hand.raised")
                    }
                    .buttonStyle(.secondary(Theme.ink))
                    .disabled(trip.isConfirmingHelp)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
            }
        }
        .helpConfirmation(isPresented: $confirmingHelp)
    }

    private var countdownRing: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = max(trip.checkInDeadline?.timeIntervalSince(context.date) ?? 0, 0)
            let fraction = remaining / max(trip.checkInWindow, 1)
            ZStack {
                Circle()
                    .stroke(Theme.primary.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: fraction)
                VStack(spacing: 2) {
                    Text(Format.countdown(remaining))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text("before we tell\nyour circle")
                        .multilineTextAlignment(.center)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(width: 160, height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Format.countdown(remaining)) before your circle is told")
        }
    }
}

#Preview {
    SmartCheckInView(reason: .unusualStop)
        .environment(AppModel.shared)
}
