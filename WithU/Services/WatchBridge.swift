//
//  WatchBridge.swift
//  WithU
//
//  Mirrors the trip state to the Watch app and applies the commands it
//  sends back (one-tap check-in, SOS, heart-rate spike).
//

import Foundation
import Observation
import OSLog
import WatchConnectivity

final class WatchBridge: NSObject {
    private let trip: TripManager
    private let settings: () -> AppSettings
    private let selectedCircle: () -> TrustedCircle
    private let startSOS: () -> Void
    private var lastSent: WatchTripSnapshot?

    init(trip: TripManager,
         settings: @escaping () -> AppSettings,
         selectedCircle: @escaping () -> TrustedCircle,
         startSOS: @escaping () -> Void) {
        self.trip = trip
        self.settings = settings
        self.selectedCircle = selectedCircle
        self.startSOS = startSOS
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        observe()
    }

    // MARK: Phone → Watch

    /// Re-runs whenever any trip property used by `makeSnapshot` changes.
    private func observe() {
        withObservationTracking {
            _ = makeSnapshot()
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.push()
                self.observe()
            }
        }
    }

    private func makeSnapshot() -> WatchTripSnapshot {
        let phase: WatchTripPhase
        var checkInTitle: String?
        switch trip.phase {
        case .idle: phase = .idle
        case .active: phase = .active
        case .checkingIn(let reason):
            phase = .checkingIn
            checkInTitle = reason.title
        case .enteringPIN, .alerting: phase = .alerting
        case .arrived: phase = .arrived
        }
        // Between trips the watch shows who an SOS would reach.
        let circle = selectedCircle()
        let contacts = trip.isActive ? trip.contacts : circle.contacts
        return WatchTripSnapshot(phase: phase,
                                 destinationName: trip.isSOSOnly ? "" : (trip.plan?.destination.name ?? ""),
                                 circleName: trip.isActive ? trip.circleName : circle.name,
                                 contactCount: contacts.count,
                                 contactNames: contacts.prefix(4).map(\.name),
                                 isSOSOnly: trip.isSOSOnly,
                                 startedAt: trip.startedAt,
                                 endsAt: trip.endsAt,
                                 checkInDeadline: trip.checkInDeadline,
                                 checkInTitle: checkInTitle,
                                 heartRatePromptEnabled: settings().heartRatePrompt,
                                 updatedAt: .now)
    }

    private let log = Logger(subsystem: "com.jahanzaibali.withu", category: "Watch")

    /// Sends the current state to the watch. `force` skips the "nothing changed"
    /// check, used when the watch may have missed earlier updates.
    func push(force: Bool = false) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        var snapshot = makeSnapshot()
        if !force, var previous = lastSent {
            previous.updatedAt = snapshot.updatedAt
            if previous == snapshot { return }
        }
        snapshot.updatedAt = .now
        lastSent = snapshot
        let context = WatchSync.context(for: snapshot)
        do {
            try session.updateApplicationContext(context)
        } catch {
            log.error("Couldn't update watch context: \(error.localizedDescription, privacy: .public)")
        }
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { [log] error in
                log.error("Couldn't message watch: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Watch → Phone

    private func handle(_ message: [String: Any]) {
        guard let command = WatchSync.command(from: message) else { return }
        switch command {
        case .checkInOK:
            trip.respondOK()
        case .sos:
            if trip.isActive {
                trip.emergency()
            } else {
                startSOS()
            }
        case .extendTenMinutes:
            if case .checkingIn = trip.phase {
                trip.respondAddingTime()
            } else {
                trip.extend()
            }
        case .heartRateSpike:
            guard settings().heartRatePrompt else { return }
            trip.triggerCheckIn(.heartRateSpike)
        case .requestState:
            break
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.push(force: true) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The paired watch changed; activate again for the new one.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.push(force: true) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handle(message)
            self.push(force: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handle(message)
            replyHandler(WatchSync.context(for: self.makeSnapshot()))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Queued commands (sent while the iPhone was out of reach) arrive here.
        Task { @MainActor in
            self.handle(userInfo)
            self.push(force: true)
        }
    }
}
