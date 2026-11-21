//
//  TripManager.swift
//  WithU
//
//  The safety state machine for a single trip: countdown, arrival detection,
//  smart check-ins, the circle alert and Face ID / PIN confirmation.
//
//  Alert rules:
//  • A missed check-in waits the reply window (15 or 20 min, from Settings),
//    with a gentle reminder 5 min before, then alerts the whole circle at once
//    with the last detected location and battery.
//  • A long stop (15 min by default) asks you to share a moment. Sharing one
//    or moving on answers it; otherwise the circle is alerted after the window.
//  • "Alert" and "I Need Help" alert the whole circle straight away.
//

import CoreLocation
import Foundation
import Observation
import UIKit

enum TripPhase: Equatable {
    case idle
    case active
    case checkingIn(CheckInReason)
    case enteringPIN
    case alerting
    case arrived
}

@Observable
final class TripManager {
    // MARK: Dependencies

    private let location: LocationService
    private let notifications: NotificationService
    private let auth: AuthenticationService
    private let liveActivity = LiveActivityService()
    /// Delivers trip updates to the circle. Local until iCloud sync is on.
    private(set) var sync: CircleSyncing = LocalCircleSync()
    private var lastLocationShare: Date = .distantPast

    // MARK: Public state

    private(set) var phase: TripPhase = .idle
    private(set) var plan: TripPlan?
    private(set) var contacts: [TrustedContact] = []
    private(set) var circleName = ""
    private var circle: TrustedCircle?
    /// The circle the running trip is shared with.
    var circleID: UUID? { circle?.id }
    private(set) var startedAt: Date = .now
    private(set) var endsAt: Date = .now
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    /// The route as drawn: walking, cycling, driving or walk + ride + walk.
    private(set) var routeLegs: [RouteLeg] = []
    private(set) var remainingDistance: CLLocationDistance?
    private(set) var checkInDeadline: Date?
    private(set) var alertStates: [ContactAlertState] = []
    private(set) var alertStartedAt: Date?
    private(set) var isAlertActive = false
    private(set) var lastSnapshot: LocationSnapshot?
    private(set) var pinError: String?
    private(set) var waitingForSignal = false
    private(set) var arrivedAt: Date?
    private(set) var extensionsAdded: TimeInterval = 0
    private(set) var isBusyRoute = false
    /// Identifies the running trip, so stories shared on the way belong to it.
    private(set) var tripID = UUID()

    /// Called when a trip ends with an arrival, to keep it in the journal.
    var onArrived: ((Journey) -> Void)?

    var currentLocation: CLLocation? { location.currentLocation }

    /// Time to answer a check-in, from Settings.
    var checkInWindow: TimeInterval { TimeInterval(settings.checkInResponseSeconds) }
    var isActive: Bool { phase != .idle }

    var respondingContact: TrustedContact? {
        alertStates.first(where: { $0.status == .onIt })?.contact
    }

    // MARK: Internals

    private var settings = AppSettings()
    private var tickTask: Task<Void, Never>?
    private var checkInTask: Task<Void, Never>?
    /// Waiting to ask again after "Remind Me Later" on a long stop.
    private var stopReminderTask: Task<Void, Never>?
    /// When that second check-in is due; saved with the trip.
    private var stopReminderAt: Date?
    /// True for the long-stop check-in that follows "Remind Me Later".
    private var isStopFollowUp = false
    private var stopAnchor: CLLocation?
    private var stoppedSince: Date?
    private var speedStrikes = 0
    private var offRouteStrikes = 0
    private var cooldowns: [CheckInReason: Date] = [:]
    private var timerExpiryHandled = false
    private var deadlineHandled = false
    private var lowBatteryPingSent = false
    private var lastProcessedFix: Date?

    init(location: LocationService, notifications: NotificationService, auth: AuthenticationService) {
        self.location = location
        self.notifications = notifications
        self.auth = auth
        sync.onContactResponse = { [weak self] id in
            self?.contactResponded(id)
        }
        notifications.onCheckInResponse = { [weak self] response in
            switch response {
            case .ok: self?.respondOK()
            case .addTime: self?.respondAddingTime()
            case .remindLater: self?.remindLater()
            case .needHelp: self?.needHelp()
            case .opened: break
            }
        }
    }

    // MARK: - Lifecycle

    func start(plan: TripPlan, route: RouteResult, circle: TrustedCircle, settings: AppSettings) {
        guard phase == .idle else { return }
        isSOSOnly = false
        tripID = UUID()
        self.plan = plan
        self.contacts = circle.contacts
        self.circleName = circle.name
        self.circle = circle
        self.settings = settings
        routeCoordinates = route.coordinates
        routeLegs = route.legs
        isBusyRoute = route.isBusyRoute
        remainingDistance = plan.distance

        startedAt = .now
        // Apple Maps estimates are tight, so give a little grace before asking.
        let grace = max(plan.expectedTravelTime * 0.15, 120)
        endsAt = startedAt.addingTimeInterval(plan.expectedTravelTime + grace)

        resetDetectors()
        alertStates = contacts.map { ContactAlertState(contact: $0, status: .notYetNotified) }
        isAlertActive = false
        arrivedAt = nil
        extensionsAdded = 0
        timerExpiryHandled = false
        deadlineHandled = false
        lowBatteryPingSent = false
        lastProcessedFix = nil
        phase = .active

        UIDevice.current.isBatteryMonitoringEnabled = true
        location.startUpdates(for: plan.mode)
        liveActivity.start(plan: plan, contacts: contacts, startDate: startedAt, endDate: endsAt)
        let ids = contacts.map(\.id)
        let end = endsAt
        Task { await sync.send(CircleMessage(kind: .tripStarted(endDate: end), contactIDs: ids)) }
        startTicking()
        save()
    }

    // MARK: - Persistence

    /// Writes the running trip to disk.
    private func save() {
        guard let plan, let circle, phase != .idle, phase != .arrived else {
            Persistence.remove(.activeTrip)
            return
        }
        var pendingCheckIn: SavedTrip.PendingCheckIn?
        if case .checkingIn(let reason) = phase, let checkInDeadline {
            pendingCheckIn = .init(reason: reason, deadline: checkInDeadline, isFollowUp: isStopFollowUp)
        }
        let saved = SavedTrip(plan: plan,
                              circle: circle,
                              startedAt: startedAt,
                              endsAt: endsAt,
                              route: routeCoordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                              isBusyRoute: isBusyRoute,
                              extensionsAdded: extensionsAdded,
                              isAlerting: isAlertActive,
                              alertStartedAt: alertStartedAt,
                              tripID: tripID,
                              legs: routeLegs,
                              isSOSOnly: isSOSOnly,
                              pendingCheckIn: pendingCheckIn,
                              stopReminderAt: stopReminderAt)
        Persistence.save(saved, for: .activeTrip)
    }

    /// Picks the trip back up after the app was closed: tracking, timers,
    /// the Live Activity and, if one was running, the alert.
    func restore(settings: AppSettings) {
        guard phase == .idle else { return }
        guard let saved = Persistence.load(SavedTrip.self, for: .activeTrip) else {
            // Nothing to resume; clear any Lock Screen activity and background
            // location session left behind.
            liveActivity.endOrphans()
            location.endLeftoverBackgroundActivity()
            return
        }
        // Builds before `isSOSOnly` was saved: an SOS is the trip to "Alert"
        // with no distance.
        let wasSOS = saved.isSOSOnly ?? (saved.plan.destination.name == "Alert" && saved.plan.distance == 0)
        if wasSOS && !saved.isAlerting {
            // An SOS that's no longer alerting has nothing left to do. Resuming
            // it kept location (and the Dynamic Island arrow) on for good.
            Persistence.remove(.activeTrip)
            liveActivity.endOrphans()
            location.endLeftoverBackgroundActivity()
            return
        }
        plan = saved.plan
        tripID = saved.tripID ?? UUID()
        circle = saved.circle
        contacts = saved.circle.contacts
        circleName = saved.circle.name
        self.settings = settings
        startedAt = saved.startedAt
        endsAt = saved.endsAt
        routeCoordinates = saved.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        routeLegs = saved.legs ?? (routeCoordinates.isEmpty ? [] : [RouteLeg(kind: saved.plan.mode.legKind, coordinates: routeCoordinates)])
        isBusyRoute = saved.isBusyRoute
        extensionsAdded = saved.extensionsAdded
        remainingDistance = saved.plan.distance
        alertStates = contacts.map { ContactAlertState(contact: $0, status: .notYetNotified) }
        resetDetectors()
        timerExpiryHandled = false
        deadlineHandled = false
        lowBatteryPingSent = false
        lastProcessedFix = nil
        isSOSOnly = wasSOS
        phase = .active

        UIDevice.current.isBatteryMonitoringEnabled = true
        location.startUpdates(for: saved.plan.mode)
        if !liveActivity.resume() {
            liveActivity.start(plan: saved.plan, contacts: contacts, startDate: startedAt, endDate: endsAt)
        }
        startTicking()

        if saved.isAlerting {
            // The alert never stops just because the app was closed.
            startAlert(trigger: .manual)
            alertStartedAt = saved.alertStartedAt ?? alertStartedAt
        } else if let pending = saved.pendingCheckIn {
            // Closing the app doesn't answer a check-in: carry on counting
            // down, or alert now if the time ran out while it was closed.
            if pending.deadline <= .now {
                startAlert(trigger: pending.reason)
            } else {
                beginCheckIn(pending.reason, deadline: pending.deadline, isFollowUp: pending.isFollowUp)
            }
        } else if let reminderAt = saved.stopReminderAt {
            if reminderAt <= .now {
                startStopFollowUp(scheduledAt: reminderAt)
            } else {
                scheduleStopReminder(at: reminderAt)
            }
        }
    }

    /// The "I've Arrived" button. Face ID (or the passcode) first, so nobody
    /// else holding the phone can switch the safety off by saying you arrived.
    /// Automatic arrival detection calls `arrive()` directly.
    @discardableResult
    func confirmArrival() async -> Bool {
        guard canArrive else { return false }
        let confirmed = await auth.authenticateOwner(reason: "Confirm it's you to end sharing")
        guard confirmed, canArrive else { return false }
        arrive()
        return true
    }

    private var canArrive: Bool { phase == .active || phase == .checkingIn(.timerExpired) }

    /// "I've arrived safely" or automatic arrival detection.
    func arrive() {
        guard phase == .active || phase == .checkingIn(.timerExpired) else { return }
        checkInTask?.cancel()
        cancelStopReminder()
        notifications.clearCheckIn()
        arrivedAt = .now
        phase = .arrived
        Persistence.remove(.activeTrip)
        tickTask?.cancel()
        location.stopUpdates()
        liveActivity.end(status: .arrived)
        if let plan {
            notifications.postArrived(destination: plan.destination.name)
            if !isSOSOnly {
                onArrived?(Journey(id: tripID,
                                   destinationName: plan.destination.name,
                                   mode: plan.mode,
                                   startedAt: startedAt,
                                   endedAt: .now,
                                   distance: plan.distance,
                                   circleName: circleName))
            }
        }
        let ids = contacts.map(\.id)
        Task { await sync.send(CircleMessage(kind: .arrived, contactIDs: ids)) }
    }

    /// Ends a trip that was started by mistake or is no longer needed. Asks for
    /// Face ID or the passcode first. Not available while an alert is running;
    /// that has to go through "I'm Safe".
    func cancelTrip() async -> Bool {
        guard phase == .active else { return false }
        let confirmed = await auth.authenticateOwner(reason: "Confirm it's you to end this trip")
        guard confirmed, phase == .active else { return false }
        notifications.clearCheckIn()
        liveActivity.endNow()
        let ids = contacts.map(\.id)
        Task { await sync.send(CircleMessage(kind: .tripCancelled, contactIDs: ids)) }
        finish()
        return true
    }

    /// Dismisses the arrival screen and wipes the trip, including the route.
    func finish() {
        tickTask?.cancel()
        checkInTask?.cancel()
        cancelStopReminder()
        location.stopUpdates()
        plan = nil
        circleName = ""
        routeCoordinates = []
        routeLegs = []
        remainingDistance = nil
        checkInDeadline = nil
        alertStates = []
        alertStartedAt = nil
        isAlertActive = false
        lastSnapshot = nil
        pinError = nil
        arrivedAt = nil
        circle = nil
        isSOSOnly = false
        phase = .idle
        Persistence.remove(.activeTrip)
    }

    func extend(by interval: TimeInterval = TripRules.extensionStep) {
        guard isActive else { return }
        endsAt = endsAt.addingTimeInterval(interval)
        extensionsAdded += interval
        timerExpiryHandled = false
        liveActivity.update(endDate: endsAt, status: .onTheWay, remainingDistance: remainingDistance)
        let ids = contacts.map(\.id)
        let end = endsAt
        Task { await sync.send(CircleMessage(kind: .tripExtended(endDate: end), contactIDs: ids)) }
        save()
    }

    // MARK: - Check-ins

    /// True when the current check-in is a first long stop, which can be put off once.
    var canRemindLater: Bool { phase == .checkingIn(.unusualStop) && !isStopFollowUp }

    func triggerCheckIn(_ reason: CheckInReason, force: Bool = false) {
        guard phase == .active else { return }
        if !force, let until = cooldowns[reason], until > .now { return }
        notifications.postCheckIn(reason: reason, window: checkInWindow)
        beginCheckIn(reason, deadline: .now.addingTimeInterval(checkInWindow), isFollowUp: false)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Shows the check-in and counts down to `deadline`, then alerts the
    /// circle. Saved with the trip so reopening the app picks the countdown up.
    private func beginCheckIn(_ reason: CheckInReason, deadline: Date, isFollowUp: Bool) {
        isStopFollowUp = isFollowUp
        checkInDeadline = deadline
        phase = .checkingIn(reason)
        liveActivity.update(endDate: endsAt, status: .checkIn, remainingDistance: remainingDistance)
        save()

        checkInTask?.cancel()
        checkInTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
            guard let self, !Task.isCancelled else { return }
            if case .checkingIn(let pending) = self.phase {
                self.startAlert(trigger: pending)
            }
        }
    }

    func respondOK() {
        guard case .checkingIn(let reason) = phase else { return }
        checkInTask?.cancel()
        notifications.clearCheckIn()
        cooldowns[reason] = .now.addingTimeInterval(TripRules.reasonCooldown)
        resetDetectors()
        checkInDeadline = nil
        phase = .active
        if reason == .timerExpired || endsAt <= .now {
            extend()
        } else {
            liveActivity.update(endDate: endsAt, status: .onTheWay, remainingDistance: remainingDistance)
        }
        save()
    }

    /// "Add 10 Min" from a check-in: confirms you're OK and gives you more time.
    func respondAddingTime() {
        guard case .checkingIn(let reason) = phase else { return }
        respondOK()
        // `respondOK` already extends when the timer ran out.
        if reason != .timerExpired { extend() }
    }

    /// "Remind Me Later" on a long stop: puts the check-in away and asks once
    /// more after `stopReminderDelay`. That second check-in can't be put off,
    /// so no reply to it alerts the circle. Moving on cancels the reminder.
    func remindLater() {
        guard canRemindLater else { return }
        checkInTask?.cancel()
        notifications.clearCheckIn()
        checkInDeadline = nil
        phase = .active
        liveActivity.update(endDate: endsAt, status: .onTheWay, remainingDistance: remainingDistance)

        // The system delivers the second check-in even if WithU is closed by then.
        let delay = TripRules.stopReminderDelay
        notifications.postCheckIn(reason: .unusualStop, window: checkInWindow, isFollowUp: true, after: delay)
        scheduleStopReminder(at: .now.addingTimeInterval(delay))
        save()
    }

    private func scheduleStopReminder(at date: Date) {
        stopReminderAt = date
        stopReminderTask?.cancel()
        stopReminderTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(date.timeIntervalSinceNow, 0)))
            guard let self, !Task.isCancelled else { return }
            self.startStopFollowUp(scheduledAt: date)
        }
    }

    /// The second long-stop check-in. Its notification was already scheduled
    /// with the system, so this only runs the countdown, timed from when it
    /// was due. If that has already run out (the app was closed), the circle
    /// is alerted straight away.
    private func startStopFollowUp(scheduledAt date: Date) {
        stopReminderTask = nil
        stopReminderAt = nil
        guard phase == .active else { return }
        let deadline = date.addingTimeInterval(checkInWindow)
        if deadline <= .now {
            startAlert(trigger: .unusualStop)
        } else {
            beginCheckIn(.unusualStop, deadline: deadline, isFollowUp: true)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func cancelStopReminder() {
        guard stopReminderAt != nil || stopReminderTask != nil else { return }
        stopReminderTask?.cancel()
        stopReminderTask = nil
        stopReminderAt = nil
        notifications.cancelScheduledCheckIn()
    }

    func needHelp() {
        guard case .checkingIn(let reason) = phase else { return }
        startAlert(trigger: reason)
    }

    /// The Emergency button: skips the check-in and alerts straight away.
    func emergency() {
        guard phase == .active || { if case .checkingIn = phase { return true } else { return false } }() else { return }
        startAlert(trigger: .manual)
    }

    /// True while Face ID is open for "Get Help", so a second tap can't start another.
    private(set) var isConfirmingHelp = false

    /// "Get Help" / "I Need Help" after the person tapped Send Alert: confirms
    /// it's really them (Face ID, passcode as fallback), then alerts the circle.
    /// Returns false when nothing was sent. The lock-screen action and the
    /// missed check-in alert don't use this; they never need Face ID.
    func requestHelp() async -> Bool {
        guard !isConfirmingHelp else { return false }
        switch phase {
        case .active, .checkingIn: break
        default: return false
        }
        isConfirmingHelp = true
        defer { isConfirmingHelp = false }
        guard await auth.authenticateOwner(reason: "Confirm it's you to alert your circle") else { return false }
        // The check-in may have run out while Face ID was open.
        switch phase {
        case .active, .checkingIn:
            emergency()
            return true
        case .alerting:
            // The alert already started on its own; nothing more to send.
            return true
        default:
            return false
        }
    }

    /// True for a session started by SOS without a planned trip: no arrival
    /// detection or movement check-ins, just location sharing and the alert.
    private(set) var isSOSOnly = false

    /// An alert when no trip is running: shares your
    /// location with the circle and alerts them straight away.
    func startSOS(circle: TrustedCircle, settings: AppSettings) {
        if isActive {
            emergency()
            return
        }
        let here = location.currentLocation?.coordinate
        let spot = Destination(name: "Alert",
                               subtitle: "",
                               latitude: here?.latitude ?? 0,
                               longitude: here?.longitude ?? 0)
        let plan = TripPlan(destination: spot,
                            mode: .walk,
                            expectedTravelTime: 3600,
                            distance: 0,
                            checkOnStop: false,
                            stopThresholdMinutes: settings.stopThresholdMinutes,
                            deadline: nil)
        start(plan: plan,
              route: RouteResult(expectedTravelTime: 3600, distance: 0, coordinates: [], isBusyRoute: false),
              circle: circle,
              settings: settings)
        isSOSOnly = true
        startAlert(trigger: .manual)
    }

    // MARK: - Alerts

    private func startAlert(trigger: CheckInReason) {
        checkInTask?.cancel()
        cancelStopReminder()
        notifications.clearCheckIn()
        checkInDeadline = nil
        alertStartedAt = .now
        isAlertActive = true
        lastSnapshot = makeSnapshot()
        phase = .alerting
        liveActivity.update(endDate: endsAt, status: .alerting, remainingDistance: remainingDistance)
        notifications.postAlertStarted(circleName: circleName)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        // Everyone in the circle at once, with the last location and battery.
        // Location keeps updating for them every minute while the alert runs.
        save()
        notify(indices: Array(alertStates.indices))
    }

    /// Swaps in the iCloud delivery layer.
    func useSync(_ newSync: CircleSyncing) {
        newSync.onContactResponse = { [weak self] id in
            self?.contactResponded(id)
        }
        sync = newSync
    }

    private func notify(indices: [Int]) {
        let valid = indices.filter { alertStates.indices.contains($0) }
        guard !valid.isEmpty else { return }
        for index in valid { alertStates[index].status = .notified }
        let ids = valid.map { alertStates[$0].contact.id }
        let snapshot = lastSnapshot
        Task { [weak self] in
            let acknowledged = await self?.sync.send(CircleMessage(kind: .alert(snapshot), contactIDs: ids)) ?? []
            guard let self, self.isAlertActive else { return }
            for index in self.alertStates.indices where self.alertStates[index].status == .notified {
                let id = self.alertStates[index].contact.id
                guard ids.contains(id) else { continue }
                // People who haven't accepted an invite can't be reached.
                self.alertStates[index].status = acknowledged.contains(id) ? .delivered : .unreachable
            }
        }
    }

    /// A contact tapped "I'm on it" on their phone, so you know help is coming.
    func contactResponded(_ contactID: UUID) {
        guard isAlertActive, let index = alertStates.firstIndex(where: { $0.contact.id == contactID }) else { return }
        alertStates[index].status = .onIt
    }

    /// "I'm safe — cancel alert". Face ID first, PIN as fallback.
    func requestCancelAlert() async {
        guard phase == .alerting else { return }
        if auth.biometryAvailable {
            let confirmed = await auth.authenticateWithBiometrics(reason: "Confirm it's you to cancel the alert")
            if confirmed {
                cancelAlert()
                return
            }
        }
        if auth.hasPIN {
            pinError = nil
            phase = .enteringPIN
        } else if !auth.biometryAvailable {
            // Nothing to verify against on this device.
            cancelAlert()
        }
    }

    func submitPIN(_ pin: String) {
        guard phase == .enteringPIN else { return }
        switch auth.verify(pin) {
        case .match:
            cancelAlert()
        case .mismatch:
            pinError = "That PIN doesn't match. Try again."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func cancelPINEntry() {
        guard phase == .enteringPIN else { return }
        pinError = nil
        phase = .alerting
    }

    private func cancelAlert() {
        isAlertActive = false
        alertStartedAt = nil
        pinError = nil
        for index in alertStates.indices { alertStates[index].status = .notYetNotified }
        let ids = contacts.map(\.id)
        Task { await sync.send(CircleMessage(kind: .allClear, contactIDs: ids)) }
        if isSOSOnly {
            // An SOS has no trip to go back to: end it completely, so location
            // sharing and the Dynamic Island arrow stop too.
            liveActivity.endNow()
            finish()
            return
        }
        resetDetectors()
        phase = .active
        if endsAt <= .now { extend() }
        liveActivity.update(endDate: endsAt, status: .onTheWay, remainingDistance: remainingDistance)
        save()
    }

    // MARK: - Ticking and detection

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        guard let plan, phase != .arrived, phase != .idle else { return }
        processNewFix()
        shareLocationIfDue()

        let now = Date.now
        if let lastProcessedFix {
            waitingForSignal = now.timeIntervalSince(lastProcessedFix) > TripRules.staleFixAge
        } else {
            waitingForSignal = true
        }

        checkBattery()
        guard phase == .active else { return }

        if now >= endsAt, !timerExpiryHandled {
            timerExpiryHandled = true
            triggerCheckIn(.timerExpired, force: true)
            return
        }
        if let deadline = plan.deadline, now >= deadline, !deadlineHandled {
            deadlineHandled = true
            triggerCheckIn(.deadlinePassed, force: true)
        }
    }

    /// Sends your position to the circle about once a minute during a trip.
    private func shareLocationIfDue() {
        guard phase != .idle, phase != .arrived,
              location.currentLocation != nil,
              Date.now.timeIntervalSince(lastLocationShare) >= 60 else { return }
        lastLocationShare = .now
        let snapshot = makeSnapshot()
        // During an alert, keep "last seen" on screen in step with what the circle gets.
        if isAlertActive { lastSnapshot = snapshot }
        let ids = contacts.map(\.id)
        Task { await sync.send(CircleMessage(kind: .location(snapshot), contactIDs: ids)) }
    }

    private func processNewFix() {
        guard let fix = location.currentLocation, fix.timestamp != lastProcessedFix else { return }
        // Coming back from a signal gap (tunnel, underground) must not count as a stop.
        if let previous = lastProcessedFix, fix.timestamp.timeIntervalSince(previous) > TripRules.staleFixAge {
            resetDetectors()
        }
        lastProcessedFix = fix.timestamp
        evaluate(fix)
    }

    private func evaluate(_ fix: CLLocation) {
        guard let plan, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 100 else { return }

        let distance = fix.distance(from: plan.destination.location)
        remainingDistance = isSOSOnly ? nil : distance

        // Moving on after a long stop answers the stop check-in.
        if case .checkingIn(.unusualStop) = phase,
           let anchor = stopAnchor,
           fix.distance(from: anchor) > TripRules.stillRadius {
            respondOK()
            return
        }

        guard phase == .active, !isSOSOnly else { return }

        // Arrival detection.
        if distance <= plan.mode.arrivalRadius {
            arrive()
            return
        }

        // Wrong speed for the travel mode.
        if let limit = plan.mode.unexpectedSpeed, fix.speed > limit {
            speedStrikes += 1
            if speedStrikes >= TripRules.strikesBeforeCheckIn {
                speedStrikes = 0
                triggerCheckIn(.unexpectedSpeed)
                return
            }
        } else {
            speedStrikes = 0
        }

        // Off route.
        if !routeCoordinates.isEmpty {
            let offset = RouteGeometry.distance(from: fix.coordinate, toPolyline: routeCoordinates)
            if offset > plan.mode.offRouteTolerance {
                offRouteStrikes += 1
                if offRouteStrikes >= TripRules.strikesBeforeCheckIn {
                    offRouteStrikes = 0
                    triggerCheckIn(.offRoute)
                    return
                }
            } else {
                offRouteStrikes = 0
            }
        }

        // Long stop.
        if let anchor = stopAnchor, let since = stoppedSince {
            if fix.distance(from: anchor) > TripRules.stillRadius {
                stopAnchor = fix
                stoppedSince = fix.timestamp
                // Moving on means there's nothing to remind about.
                if stopReminderAt != nil {
                    cancelStopReminder()
                    save()
                }
            } else if plan.checkOnStop, stopReminderTask == nil,
                      fix.timestamp.timeIntervalSince(since) >= TimeInterval(plan.stopThresholdMinutes * 60) {
                stoppedSince = fix.timestamp
                triggerCheckIn(.unusualStop)
            }
        } else {
            stopAnchor = fix
            stoppedSince = fix.timestamp
        }
    }

    private func resetDetectors() {
        stopAnchor = nil
        stoppedSince = nil
        speedStrikes = 0
        offRouteStrikes = 0
    }

    private func checkBattery() {
        guard settings.lowBatteryPing, !lowBatteryPingSent else { return }
        let level = Double(UIDevice.current.batteryLevel)
        guard level >= 0, level <= TripRules.lowBatteryLevel else { return }
        lowBatteryPingSent = true
        let snapshot = makeSnapshot()
        lastSnapshot = snapshot
        let ids = contacts.map(\.id)
        Task { await sync.send(CircleMessage(kind: .location(snapshot), contactIDs: ids)) }
    }

    /// The last place the phone was detected and the battery. Never pretends:
    /// no fix means "location unknown" (not the destination), an unknown
    /// battery stays unknown (not 100%), and the time is when the fix was taken.
    private func makeSnapshot() -> LocationSnapshot {
        let battery = Double(UIDevice.current.batteryLevel)
        let batteryLevel: Double? = battery >= 0 ? battery : nil
        guard let fix = location.currentLocation else {
            return LocationSnapshot(latitude: 0, longitude: 0, batteryLevel: batteryLevel,
                                    timestamp: .now, hasLocation: false)
        }
        return LocationSnapshot(latitude: fix.coordinate.latitude,
                                longitude: fix.coordinate.longitude,
                                batteryLevel: batteryLevel,
                                timestamp: fix.timestamp)
    }
}
