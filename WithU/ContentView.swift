//
//  ContentView.swift
//  WithU
//
//  Root router: onboarding → tabs, with the trip flow presented full screen
//  whenever a trip is running.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                MainTabView()
                    // Someone in your circle sent an SOS.
                    .fullScreenCover(item: incomingSOS) { sos in
                        IncomingSOSView(trip: sos,
                                        hasResponded: model.cloud?.hasResponded(to: sos) ?? false,
                                        onOnIt: { Task { await model.cloud?.sendOnIt(to: sos) } },
                                        onClose: { model.cloud?.dismissSOS(sos) })
                            .preferredColorScheme(model.settings.appearance.colorScheme)
                    }
            } else {
                OnboardingFlowView()
            }
        }
        .fullScreenCover(isPresented: tripPresented) {
            TripFlowView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.refreshPermissions()
                    await model.cloud?.refresh()
                }
            }
        }
        .onOpenURL { url in
            model.handle(url: url)
        }
    }

    /// Shown full screen unless you're on your own trip, which stays on top.
    private var incomingSOS: Binding<FollowedTrip?> {
        Binding(
            get: { model.trip.isActive ? nil : model.cloud?.activeSOS },
            set: { newValue in
                if newValue == nil, let sos = model.cloud?.activeSOS {
                    model.cloud?.dismissSOS(sos)
                }
            }
        )
    }

    private var tripPresented: Binding<Bool> {
        Binding(
            get: { model.trip.isActive },
            set: { _ in }
        )
    }
}

/// Switches between the trip screens as the safety state machine moves.
struct TripFlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.trip.phase {
            case .idle:
                ScreenBackground()
            case .active:
                ActiveTripView()
                    .transition(.opacity)
            case .checkingIn(let reason):
                SmartCheckInView(reason: reason)
                    .transition(.opacity)
            case .enteringPIN:
                PINEntryView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .alerting:
                AlertingCircleView()
                    .transition(.opacity)
            case .arrived:
                ArrivedView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.trip.phase)
        .interactiveDismissDisabled()
    }
}

#Preview {
    ContentView()
        .environment(AppModel.shared)
}
