//
//  CircleSyncService.swift
//  WithU
//
//  The transport that carries trip state, live location and alerts to the
//  circle's phones. Every message goes through `CircleSyncing`, so the
//  device-to-device layer can be swapped in without touching the safety logic.
//
//  The current implementation is `LocalCircleSync`: it keeps everything on this
//  device and acknowledges deliveries locally. A CloudKit/APNs-backed
//  implementation would:
//    • look up which contacts have WithU (by hashed phone number),
//    • push the trip timer to their phones so a backup timer raises the alert
//      if this phone dies or goes offline,
//    • stream the encrypted live location only while a trip is active,
//    • deliver "I'm on it" taps back to this device.
//

import Foundation

nonisolated struct CircleMessage: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case tripStarted(endDate: Date)
        case tripExtended(endDate: Date)
        case location(LocationSnapshot)
        case checkInMissed
        case alert(LocationSnapshot?)
        case allClear
        case tripCancelled
        case arrived
    }
    var kind: Kind
    var contactIDs: [UUID]
    var sentAt: Date = .now
}

protocol CircleSyncing: AnyObject {
    /// Called when a contact responds to an alert (e.g. taps "I'm on it").
    var onContactResponse: ((UUID) -> Void)? { get set }
    /// Returns the subset of contact IDs whose phones acknowledged the message.
    @discardableResult
    func send(_ message: CircleMessage) async -> Set<UUID>
}

/// Device-local stand-in for the networking layer.
final class LocalCircleSync: CircleSyncing {
    var onContactResponse: ((UUID) -> Void)?
    private(set) var outbox: [CircleMessage] = []

    @discardableResult
    func send(_ message: CircleMessage) async -> Set<UUID> {
        outbox.append(message)
        // Brief delay so the UI moves from "Sending…" to "Just received".
        try? await Task.sleep(for: .seconds(2))
        return Set(message.contactIDs)
    }
}
