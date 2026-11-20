//
//  ArrivedView.swift
//  WithU
//

import SwiftUI

struct ArrivedView: View {
    @Environment(AppModel.self) private var model
    @State private var showingRecap = false

    private var trip: TripManager { model.trip }
    private var journey: Journey? { model.stories.journeys.first { $0.id == trip.tripID } }
    private var moments: [Story] { model.stories.stories(forTrip: trip.tripID) }

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

                if !moments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(moments) { story in
                                StoryThumbnail(story: story, size: 72)
                            }
                        }
                        .padding(.horizontal, 36)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    if journey != nil {
                        Button {
                            showingRecap = true
                        } label: {
                            Label(moments.isEmpty ? "View Trip Recap" : "View Recap · \(moments.count) \(moments.count == 1 ? "Moment" : "Moments")",
                                  systemImage: "sparkles")
                        }
                        .buttonStyle(.primary)
                        Button("Done") { trip.finish() }
                            .buttonStyle(.secondary)
                    } else {
                        Button("Done") { trip.finish() }
                            .buttonStyle(.primary)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingRecap) {
            if let journey {
                NavigationStack {
                    TripRecapView(journey: journey)
                        .storyDestinations()
                }
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
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
