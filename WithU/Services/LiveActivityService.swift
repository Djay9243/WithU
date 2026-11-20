//
//  LiveActivityService.swift
//  WithU
//
//  Puts the trip countdown on the Lock Screen and in the Dynamic Island.
//  The UI lives in the WithUWidgets extension.
//

import ActivityKit
import Foundation

final class LiveActivityService {
    private var activity: Activity<TripActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(plan: TripPlan, contacts: [TrustedContact], startDate: Date, endDate: Date) {
        guard isSupported else { return }
        endExistingActivities()
        let attributes = TripActivityAttributes(
            destinationName: plan.destination.name,
            travelModeSymbol: plan.mode.symbol,
            contactInitials: contacts.prefix(3).map(\.initials),
            startDate: startDate
        )
        let state = TripActivityAttributes.ContentState(endDate: endDate, status: .onTheWay, remainingDistanceMeters: plan.distance)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: endDate.addingTimeInterval(15 * 60)),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    /// Reattaches to the activity that is still on the Lock Screen after the app
    /// was closed. Returns false when there is none.
    @discardableResult
    func resume() -> Bool {
        activity = Activity<TripActivityAttributes>.activities.first
        return activity != nil
    }

    /// Removes the Lock Screen countdown straight away, e.g. when a trip is cancelled.
    func endNow() {
        endExistingActivities()
        activity = nil
    }

    /// Ends Live Activities left over from a trip that no longer exists.
    func endOrphans() {
        endExistingActivities()
        activity = nil
    }

    func update(endDate: Date, status: TripActivityAttributes.Status, remainingDistance: Double?) {
        guard let activity else { return }
        let state = TripActivityAttributes.ContentState(endDate: endDate, status: status, remainingDistanceMeters: remainingDistance)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: endDate.addingTimeInterval(15 * 60)))
        }
    }

    func end(status: TripActivityAttributes.Status) {
        guard let activity else { return }
        let state = TripActivityAttributes.ContentState(endDate: .now, status: status, remainingDistanceMeters: 0)
        self.activity = nil
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(60)))
        }
    }

    private func endExistingActivities() {
        for existing in Activity<TripActivityAttributes>.activities {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
