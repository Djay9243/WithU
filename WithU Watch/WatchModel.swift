//
//  WatchModel.swift
//  WithU Watch
//
//  Mirrors the trip from iPhone, answers check-ins, and runs SOS from the
//  wrist at any time, with or without a trip.
//

import Foundation
import Observation
import WatchConnectivity
import WatchKit

@Observable
final class WatchModel: NSObject {
    private(set) var snapshot: WatchTripSnapshot = .idle
    private(set) var isPhoneReachable = false
    /// Set while the SOS cancel countdown is running.
    private(set) var sosFiresAt: Date?
    /// What started the countdown, shown on screen.
    private(set) var sosTrigger: SOSTrigger = .button
    /// True after an SOS was sent until the iPhone confirms it.
    private(set) var sosQueued = false
    private var resyncTask: Task<Void, Never>?

    let heartRate = HeartRateMonitor()
    let shake = ShakeDetector()

    /// Shake-to-SOS can be turned off on the watch.
    var shakeEnabled: Bool = UserDefaults.standard.object(forKey: "withu.watch.shake") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(shakeEnabled, forKey: "withu.watch.shake")
            updateShakeDetection()
        }
    }

    static let sosCancelWindow: TimeInterval = 5

    enum SOSTrigger {
        case button, doubleTap, shake
        var label: String {
            switch self {
            case .button: "SOS pressed"
            case .doubleTap: "Double Tap detected"
            case .shake: "Shake detected"
            }
        }
    }

    private var sosTask: Task<Void, Never>?
    private var lastSpikeReported: Date?
    private var isForeground = true

    override init() {
        super.init()
        heartRate.onSpike = { [weak self] bpm in
            self?.reportHeartRateSpike(bpm)
        }
        shake.onShake = { [weak self] in
            self?.beginSOS(.shake)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        updateShakeDetection()
    }

    var canSendSOS: Bool {
        sosFiresAt == nil && snapshot.phase != .alerting
    }

    // MARK: SOS

    /// Starts the cancel countdown, then alerts the circle.
    func beginSOS(_ trigger: SOSTrigger) {
        guard canSendSOS else { return }
        sosTrigger = trigger
        WKInterfaceDevice.current().play(.start)
        sosFiresAt = .now.addingTimeInterval(Self.sosCancelWindow)
        sosTask?.cancel()
        sosTask = Task { [weak self] in
            for _ in 0..<Int(Self.sosCancelWindow) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                WKInterfaceDevice.current().play(.directionUp)
            }
            guard !Task.isCancelled, let self else { return }
            self.sendSOSNow()
        }
    }

    func cancelSOS() {
        sosTask?.cancel()
        sosTask = nil
        sosFiresAt = nil
        WKInterfaceDevice.current().play(.stop)
    }

    /// Skips the countdown, e.g. "I Need Help" during a check-in.
    func sendSOSNow() {
        sosTask?.cancel()
        sosFiresAt = nil
        send(.sos)
        // Shown as "waiting" until the iPhone's reply or next update confirms it.
        sosQueued = true
        snapshot.phase = .alerting
        WKInterfaceDevice.current().play(.notification)
        scheduleResync()
    }

    /// Asks the iPhone for its current state. Whatever it reports replaces what
    /// the watch assumed, e.g. after the alert is cancelled on the phone.
    func requestState() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(WatchSync.message(for: .requestState), replyHandler: { [weak self] reply in
            guard let snapshot = WatchSync.snapshot(from: reply) else { return }
            Task { @MainActor in self?.apply(snapshot) }
        }, errorHandler: nil)
    }

    /// Re-checks a few times after an SOS in case an update is missed.
    private func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            for delay in [2, 5, 15, 30] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.snapshot.phase == .alerting else { return }
                self.requestState()
            }
        }
    }

    // MARK: Check-ins

    func respondOK() {
        WKInterfaceDevice.current().play(.success)
        send(.checkInOK)
        snapshot.phase = .active
        snapshot.checkInDeadline = nil
        snapshot.checkInTitle = nil
    }

    /// From a check-in: confirms you're OK and adds 10 minutes.
    func extendTenMinutes() {
        WKInterfaceDevice.current().play(.success)
        send(.extendTenMinutes)
        snapshot.endsAt = snapshot.endsAt.addingTimeInterval(600)
        snapshot.phase = .active
        snapshot.checkInDeadline = nil
        snapshot.checkInTitle = nil
    }

    // MARK: App state

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        updateShakeDetection()
        if foreground { requestState() }
    }

    private func updateShakeDetection() {
        if shakeEnabled && isForeground {
            shake.start()
        } else {
            shake.stop()
        }
    }

    // MARK: Heart rate

    private func reportHeartRateSpike(_ bpm: Double) {
        guard snapshot.phase == .active, snapshot.heartRatePromptEnabled else { return }
        if let last = lastSpikeReported, Date.now.timeIntervalSince(last) < 300 { return }
        lastSpikeReported = .now
        send(.heartRateSpike, heartRate: bpm)
    }

    private func updateHeartRateMonitoring() {
        if snapshot.phase == .active, snapshot.heartRatePromptEnabled {
            Task { await heartRate.start() }
        } else if snapshot.phase == .idle || snapshot.phase == .arrived {
            heartRate.stop()
        }
    }

    // MARK: Sync

    private func apply(_ incoming: WatchTripSnapshot) {
        let previousPhase = snapshot.phase
        snapshot = incoming
        if incoming.phase == .checkingIn, previousPhase != .checkingIn {
            WKInterfaceDevice.current().play(.notification)
        }
        // Any state from the iPhone means it has caught up with the watch.
        sosQueued = false
        if incoming.phase == .alerting || incoming.phase == .arrived {
            sosTask?.cancel()
            sosFiresAt = nil
        }
        updateHeartRateMonitoring()
    }

    private func send(_ command: WatchCommand, heartRate: Double? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let message = WatchSync.message(for: command, heartRate: heartRate)
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                if let snapshot = WatchSync.snapshot(from: reply) {
                    Task { @MainActor in self?.apply(snapshot) }
                }
            }, errorHandler: { _ in
                // Queued and delivered as soon as the iPhone is reachable.
                session.transferUserInfo(message)
            })
        } else {
            session.transferUserInfo(message)
        }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPhoneReachable = reachable
            if let snapshot = WatchSync.snapshot(from: context) {
                self.apply(snapshot)
            }
            self.requestState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPhoneReachable = reachable
            if reachable { self.requestState() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchSync.snapshot(from: applicationContext) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let snapshot = WatchSync.snapshot(from: message) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }
}
