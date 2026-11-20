//
//  SmartCheckInView.swift
//  WithU
//
//  "Are you OK?" with a short countdown. No answer alerts the circle.
//

import SwiftUI

struct SmartCheckInView: View {
    @Environment(AppModel.self) private var model
    var reason: CheckInReason

    private var trip: TripManager { model.trip }

    var body: some View {
        ZStack {
            ScreenBackground(tone: .alert)
            VStack(spacing: 20) {
                StatusPill(text: "Check-In", tint: Theme.alertRed)
                    .padding(.top, 12)
                Spacer()
                countdownRing
                VStack(spacing: 8) {
                    Text("Are You OK?")
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
                    Button("I'm OK") {
                        trip.respondOK()
                    }
                    .buttonStyle(.primary(Theme.deepGreen))
                    Button {
                        trip.respondAddingTime()
                    } label: {
                        Label("Add 10 Min", systemImage: "plus")
                    }
                    .buttonStyle(.secondary(Theme.ink))
                    Button("I Need Help") {
                        trip.needHelp()
                    }
                    .buttonStyle(.primary(Theme.alertRed))
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
            }
        }
    }

    private var countdownRing: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = max(trip.checkInDeadline?.timeIntervalSince(context.date) ?? 0, 0)
            let fraction = remaining / max(trip.checkInWindow, 1)
            ZStack {
                Circle()
                    .stroke(Theme.alertRed.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.alertRed, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: fraction)
                VStack(spacing: 2) {
                    Text(Format.countdown(remaining))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text("to reply")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(width: 150, height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Format.countdown(remaining)) left to reply")
        }
    }
}

#Preview {
    SmartCheckInView(reason: .unusualStop)
        .environment(AppModel.shared)
}
