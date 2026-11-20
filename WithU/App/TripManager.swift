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
                              legs: routeLegs)
        Persistence.save(saved, for: .activeTrip)
    }

    /// Picks the trip back up after the app was closed: tracking, timers,
    /// the Live Activity and, if one was running, the alert.
    func restore(settings: AppSettings) {
        guard phase == .idle else { return }
        guard let saved = Persistence.load(SavedTrip.self, for: .activeTrip) else {
            // Nothing to resume; clear any Lock Screen activity left behind.
            liveActivity.endOrphans()
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

    func triggerCheckIn(_ reason: CheckInReason, force: Bool = false) {
        guard phase == .active else { return }
        if !force, let until = cooldowns[reason], until > .now { return }
        checkInDeadline = .now.addingTimeInterval(checkInWindow)
        phase = .checkingIn(reason)
        notifications.postCheckIn(reason: reason, window: checkInWindow)
        liveActivity.update(endDate: endsAt, status: .checkIn, remainingDistance: remainingDistance)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        checkInTask?.cancel()
        checkInTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.checkInWindow ?? 120))
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
    }

    /// "Add 10 Min" from a check-in: confirms you're OK and gives you more time.
    func respondAddingTime() {
        guard case .checkingIn(let reason) = phase else { return }
        respondOK()
        // `respondOK` already extends when the timer ran out.
        if reason != .timerExpired { extend() }
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
            } else if plan.checkOnStop,
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
