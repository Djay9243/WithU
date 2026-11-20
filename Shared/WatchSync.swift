//
//  WatchSync.swift
//  WithU
//
//  Messages exchanged between the iPhone app and the Watch app over
//  WatchConnectivity. Compiled into both targets.
//

import Foundation

nonisolated enum WatchTripPhase: String, Codable, Sendable {
    case idle, active, checkingIn, alerting, arrived
}

/// Everything the watch needs to show the trip and act on it.
nonisolated struct WatchTripSnapshot: Codable, Sendable, Equatable {
    var phase: WatchTripPhase
    var destinationName: String
    var circleName: String
    var contactCount: Int
    var contactNames: [String] = []
    /// An SOS started without a planned trip.
    var isSOSOnly: Bool = false
    var startedAt: Date
    var endsAt: Date
    var checkInDeadline: Date?
    var checkInTitle: String?
    var heartRatePromptEnabled: Bool
    var updatedAt: Date

    static let idle = WatchTripSnapshot(phase: .idle,
                                        destinationName: "",
                                        circleName: "",
                                        contactCount: 0,
                                        startedAt: .now,
                                        endsAt: .now,
                                        checkInDeadline: nil,
                                        checkInTitle: nil,
                                        heartRatePromptEnabled: false,
                                        updatedAt: .now)
}

/// Actions the watch can send back to the phone.
nonisolated enum WatchCommand: String, Codable, Sendable {
    case checkInOK
    case sos
    case extendTenMinutes
    case heartRateSpike
    /// The watch asks for the current state; the reply carries it.
    case requestState
}

nonisolated enum WatchSync {
    static let snapshotKey = "withu.snapshot"
    static let commandKey = "withu.command"
    static let heartRateKey = "withu.heartRate"

    static func context(for snapshot: WatchTripSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else { return [:] }
        return [snapshotKey: data]
    }

    static func snapshot(from context: [String: Any]) -> WatchTripSnapshot? {
        guard let data = context[snapshotKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchTripSnapshot.self, from: data)
    }

    static func message(for command: WatchCommand, heartRate: Double? = nil) -> [String: Any] {
        var message: [String: Any] = [commandKey: command.rawValue]
        if let heartRate { message[heartRateKey] = heartRate }
        return message
    }

    static func command(from message: [String: Any]) -> WatchCommand? {
        guard let raw = message[commandKey] as? String else { return nil }
        return WatchCommand(rawValue: raw)
    }
}
