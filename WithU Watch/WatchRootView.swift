//
//  WatchRootView.swift
//  WithU Watch
//
//  SOS is on every screen. Tap it, use Double Tap, or shake your wrist;
//  a five-second countdown lets you cancel before your circle is alerted.
//

import SwiftUI

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        Group {
            if model.sosFiresAt != nil {
                SOSCountdownView()
            } else {
                switch model.snapshot.phase {
                case .idle: HomeView()
                case .active: TripCountdownView()
                case .checkingIn: CheckInView()
                case .alerting: AlertingView()
                case .arrived: ArrivedView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.snapshot.phase)
        .animation(.easeInOut(duration: 0.25), value: model.sosFiresAt != nil)
    }
}

// MARK: - SOS button

/// Big red button. Tapping it or using Double Tap starts the SOS countdown.
private struct SOSButton: View {
    @Environment(WatchModel.self) private var model
    var size: CGFloat = 96

    var body: some View {
        Button {
            model.beginSOS(.button)
        } label: {
            ZStack {
                Circle()
                    .fill(WatchTheme.alert.gradient)
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 3)
                VStack(spacing: 0) {
                    Text("SOS")
                        .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                    Text("Tap or Double Tap")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .disabled(!model.canSendSOS)
        .accessibilityLabel("SOS")
        .accessibilityHint("Starts a five-second countdown, then alerts your circle.")
    }
}

// MARK: - Home

private struct HomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 12) {
                SOSButton(size: 104)
                    .padding(.top, 4)

                VStack(spacing: 2) {
                    Text(model.snapshot.circleName.isEmpty ? "Your Circle" : model.snapshot.circleName)
                        .font(.headline)
                    Text(circleSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Toggle(isOn: $model.shakeEnabled) {
                    Label("Shake for SOS", systemImage: "hand.wave.fill")
                        .font(.footnote)
                }
                .tint(WatchTheme.safe)

                ConnectionLabel()
            }
            .padding(.horizontal, 4)
        }
    }

    private var circleSummary: String {
        let names = model.snapshot.contactNames
        guard !names.isEmpty else { return "Add people on your iPhone" }
        let shown = names.formatted(.list(type: .and))
        let extra = model.snapshot.contactCount - names.count
        return extra > 0 ? "\(shown) and \(extra) more" : shown
    }
}

private struct ConnectionLabel: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        Label(model.isPhoneReachable ? "iPhone Connected" : "iPhone Not Reachable",
              systemImage: model.isPhoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
            .font(.caption2)
            .foregroundStyle(model.isPhoneReachable ? Color.secondary : WatchTheme.warning)
    }
}

// MARK: - Active trip

private struct TripCountdownView: View {
    @Environment(WatchModel.self) private var model

    private var snapshot: WatchTripSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(snapshot.isSOSOnly ? "Sharing Location" : snapshot.destinationName)
                    .font(.headline)
                    .lineLimit(1)

                if !snapshot.isSOSOnly {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Gauge(value: progress(at: context.date)) {
                            EmptyView()
                        } currentValueLabel: {
                            Text(timerInterval: snapshot.startedAt...max(snapshot.endsAt, snapshot.startedAt.addingTimeInterval(1)),
                                 countsDown: true,
                                 showsHours: false)
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(WatchTheme.primary)
                        .scaleEffect(1.4)
                        .frame(height: 86)
                    }
                }

                Text("With \(snapshot.circleName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let bpm = model.heartRate.latestBPM, snapshot.heartRatePromptEnabled {
                    Label("\(Int(bpm)) BPM", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }

                SOSButton(size: 84)
            }
            .padding(.horizontal, 4)
        }
    }

    private func progress(at date: Date) -> Double {
        let total = snapshot.endsAt.timeIntervalSince(snapshot.startedAt)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(snapshot.startedAt) / total, 0), 1)
    }
}

// MARK: - Check-in

private struct CheckInView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let remaining = max(model.snapshot.checkInDeadline?.timeIntervalSince(context.date) ?? 0, 0)
                    let seconds = Int(remaining.rounded(.up))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.alert)
                }
                Text("Are You OK?")
                    .font(.headline)
                if let title = model.snapshot.checkInTitle {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    model.respondOK()
                } label: {
                    Label("I'm OK", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.safe)
                .buttonStyle(.borderedProminent)
                .handGestureShortcut(.primaryAction)

                Button {
                    model.extendTenMinutes()
                } label: {
                    Label("Add 10 Min", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.primary)

                Button(role: .destructive) {
                    model.sendSOSNow()
                } label: {
                    Label("I Need Help", systemImage: "sos")
                        .labelStyle(.titleOnly)
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.alert)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - SOS cancel window

private struct SOSCountdownView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Text(model.sosTrigger.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = max(model.sosFiresAt?.timeIntervalSince(context.date) ?? 0, 0)
                ZStack {
                    Circle()
                        .stroke(WatchTheme.alert.opacity(0.25), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: remaining / WatchModel.sosCancelWindow)
                        .stroke(WatchTheme.alert, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 84, height: 84)
            }
            Text("Alerting Your Circle")
                .font(.headline)
            Button("Cancel") {
                model.cancelSOS()
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray)
            .handGestureShortcut(.primaryAction)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Alerting / arrived

private struct AlertingView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(WatchTheme.alert)
                Text(model.sosQueued ? "Sending SOS…" : "SOS Sent")
                    .font(.headline)
                Text(model.sosQueued
                     ? "Waiting for your iPhone to confirm."
                     : "\(model.snapshot.circleName.isEmpty ? "Your circle" : model.snapshot.circleName) has your location.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("To cancel, tap I'm Safe on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    model.requestState()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.isPhoneReachable)
                ConnectionLabel()
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct ArrivedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 38))
                .foregroundStyle(WatchTheme.safe)
            Text("You've Arrived")
                .font(.headline)
            Text("Your circle has been told. Sharing stopped.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
    }
}

enum WatchTheme {
    static let primary = Color(red: 0.56, green: 0.51, blue: 0.88)
    static let safe = Color(red: 0.36, green: 0.70, blue: 0.44)
    static let alert = Color(red: 0.90, green: 0.32, blue: 0.32)
    static let warning = Color(red: 0.97, green: 0.72, blue: 0.36)
}

#Preview {
    WatchRootView()
        .environment(WatchModel())
}
