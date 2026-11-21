//
//  StopMomentView.swift
//  WithU
//
//  A long stop is usually something good: a café, a view, a friend. So the
//  prompt asks about that first. Sharing a moment or tapping "All Good" also
//  answers the safety check; no answer still alerts the circle as before.
//

import SwiftUI

struct StopMomentView: View {
    @Environment(AppModel.self) private var model
    @State private var composing = false
    @State private var confirmingHelp = false

    private var trip: TripManager { model.trip }

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.lavenderDeep)
                        .frame(width: 132, height: 132)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    StatusPill(text: "You've stopped for a while", tint: Theme.primary)
                    Text("Found something nice?")
                        .font(.title.bold())
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text("Share it with your circle.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()

                VStack(spacing: 12) {
                    Button {
                        composing = true
                    } label: {
                        Label("Share a Moment", systemImage: "camera.fill")
                    }
                    .buttonStyle(.primary)

                    Button {
                        trip.respondOK()
                    } label: {
                        Label("All Good", systemImage: "hand.thumbsup.fill")
                    }
                    .buttonStyle(.secondary(Theme.ink))

                    if trip.canRemindLater {
                        Button {
                            trip.remindLater()
                        } label: {
                            Label("Remind Me Later", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.secondary(Theme.ink))
                    }

                    Button {
                        confirmingHelp = true
                    } label: {
                        Label("I Need Help", systemImage: "hand.raised")
                    }
                    .buttonStyle(.secondary(Theme.ink))
                    .disabled(trip.isConfirmingHelp)

                    reminder
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
            }
        }
        .helpConfirmation(isPresented: $confirmingHelp)
        .sheet(isPresented: $composing) {
            StoryComposerView { _ in
                // Sharing shows you're fine, so the check-in is answered.
                trip.respondOK()
            }
            .environment(model)
            .preferredColorScheme(model.settings.appearance.colorScheme)
        }
    }

    /// A quiet note of when the circle will be checked with.
    private var reminder: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(trip.checkInDeadline?.timeIntervalSince(context.date) ?? 0, 0)
            Label("No reply in \(Format.countdown(remaining)) and we'll let your circle know",
                  systemImage: "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    StopMomentView()
        .environment(AppModel.shared)
}
