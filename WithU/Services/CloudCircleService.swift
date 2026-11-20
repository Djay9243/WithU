//
//  CloudCircleService.swift
//  WithU
//
//  Delivers trips, live location and alerts to people in your circle who
//  have WithU, using CloudKit. No accounts: everyone is identified by their
//  iCloud user.
//
//  How it works
//  • Adding someone sends an Invite addressed to a hash of their phone number.
//  • On their phone, WithU finds invites for their own number (from their
//    contact card) and shows Accept / Decline. The answer is an InviteReply.
//  • Once accepted, your trip events list their iCloud user as a recipient.
//    CloudKit subscriptions turn new events into push notifications.
//  • Their "On It" comes back to you as an OnIt record.
//
//  Every record is created by its sender and never edited by anyone else, so
//  the default public-database permissions are enough.
//
//  Turning it on (needs a paid Apple Developer Program team)
//  1. Signing & Capabilities → + iCloud → tick CloudKit, use the default container.
//  2. + Push Notifications.
//  3. Set WithUCloudSyncEnabled to YES in the target's Info.
//  4. In CloudKit Console, development schema: mark these fields Queryable
//     and Sortable as listed in `Schema` below, then deploy to production.
//

import CloudKit
import CryptoKit
import Foundation
import Observation
import UIKit

// MARK: - Public types

nonisolated struct IncomingInvite: Identifiable, Hashable, Sendable {
    var id: String
    var fromUser: String
    var fromName: String
    var circleName: String
    var sentAt: Date
}

/// Someone who shared a trip with you.
nonisolated struct FollowedTrip: Identifiable, Hashable, Sendable {
    nonisolated enum State: String, Sendable {
        case onTheWay, needsHelp, safe, arrived, ended
    }
    var id: String { fromUser }
    var fromUser: String
    var name: String
    var destination: String?
    var state: State
    var endsAt: Date?
    var latitude: Double?
    var longitude: Double?
    var battery: Double?
    var updatedAt: Date
    /// When the current state began, e.g. when the SOS was sent.
    var stateSince: Date
    /// So you can call them from the SOS screen.
    var phone: String?

    var isActive: Bool { state == .onTheWay || state == .needsHelp || state == .safe }
    /// Identifies one SOS, so closing its screen doesn't reopen it.
    var sosKey: String { "\(fromUser)-\(stateSince.timeIntervalSince1970)" }
}

// MARK: - Service

@Observable
final class CloudCircleService: CircleSyncing {
    /// Flip `WithUCloudSyncEnabled` in Info.plist once the iCloud capability is on.
    /// Touching CloudKit without the entitlement crashes, so nothing runs before that.
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "WithUCloudSyncEnabled") as? Bool ?? false
    }

    private enum Schema {
        // Fields to mark Queryable in CloudKit Console:
        //   Invite.toPhoneHash, InviteReply.toUser, OnIt.toUser,
        //   TripEvent.recipients, TripUpdate.recipients, and recordName on all.
        // Mark createdAt Queryable + Sortable on all record types.
        static let invite = "Invite"
        static let inviteReply = "InviteReply"
        static let tripEvent = "TripEvent"     // notifies recipients
        static let tripUpdate = "TripUpdate"   // quiet: location and extra time
        static let onIt = "OnIt"
    }

    var onContactResponse: ((UUID) -> Void)?

    private(set) var isAvailable = false
    private(set) var problem: String?
    private(set) var incomingInvites: [IncomingInvite] = []
    private(set) var following: [FollowedTrip] = []
    /// SOS screens the person has closed, and SOSes they answered with "On It".
    private(set) var dismissedSOS: Set<String> = []
    private(set) var respondedSOS: Set<String> = []

    /// The SOS to show full screen, if someone you follow needs help.
    var activeSOS: FollowedTrip? {
        following.first { $0.state == .needsHelp && !dismissedSOS.contains($0.sosKey) }
    }

    func dismissSOS(_ trip: FollowedTrip) {
        dismissedSOS.insert(trip.sosKey)
    }

    /// Shows a closed SOS screen again, e.g. from the Following list.
    func reopenSOS(_ trip: FollowedTrip) {
        dismissedSOS.remove(trip.sosKey)
    }

    func hasResponded(to trip: FollowedTrip) -> Bool {
        respondedSOS.contains(trip.sosKey)
    }

    // Supplied by AppModel.
    var contactLookup: (UUID) -> TrustedContact? = { _ in nil }
    var contactForRemoteUser: (String) -> TrustedContact? = { _ in nil }
    var applyInviteReply: (_ inviteID: String, _ remoteUserID: String, _ accepted: Bool) -> Void = { _, _, _ in }
    var myName: () -> String = { "Someone" }
    var myPhone: () -> String? = { nil }
    var currentDestination: () -> String? = { nil }

    private let container: CKContainer
    private var database: CKDatabase { container.publicCloudDatabase }
    private var myUserID: String?
    private var tripStartedAt: Date = .distantPast
    private var handledOnIt = Set<String>()
    private var responsePoll: Task<Void, Never>?

    private static let answeredInvitesKey = "withu.cloud.answeredInvites"
    private var answeredInvites: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.answeredInvitesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.answeredInvitesKey) }
    }

    init() {
        container = CKContainer.default()
    }

    // MARK: Lifecycle

    func start() async {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                problem = "Sign in to iCloud to reach your circle."
                return
            }
            myUserID = try await container.userRecordID().recordName
            isAvailable = true
            problem = nil
            UIApplication.shared.registerForRemoteNotifications()
            await saveSubscriptions()
            await refresh()
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Re-reads invites, replies, followed trips and "On It" responses.
    func refresh() async {
        guard isAvailable, let me = myUserID else { return }
        await refreshIncomingInvites()
        await refreshInviteReplies(me: me)
        await refreshFollowing(me: me)
        await refreshResponses(me: me)
    }

    /// Call after your phone number is added so invites to it start arriving.
    func phoneNumberChanged() async {
        await saveSubscriptions()
        await refreshIncomingInvites()
    }

    // MARK: Invites

    /// Sends an invite to the contact's phone number. Returns the invite ID.
    func sendInvite(to contact: TrustedContact, circleName: String) async -> String? {
        guard isAvailable, let me = myUserID,
              let phone = contact.phoneNumber, let hash = Self.phoneHash(phone) else { return nil }
        let name = myName()
        let record = CKRecord(recordType: Schema.invite)
        record["fromUser"] = me
        record["fromName"] = name
        record["circleName"] = circleName
        record["toPhoneHash"] = hash
        record["createdAt"] = Date.now
        record["title"] = "Circle Invite"
        record["body"] = "\(name) wants to add you to their circle on WithU."
        do {
            return try await database.save(record).recordID.recordName
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }

    func answer(_ invite: IncomingInvite, accept: Bool) async {
        guard isAvailable, let me = myUserID else { return }
        let name = myName()
        let record = CKRecord(recordType: Schema.inviteReply)
        record["inviteID"] = invite.id
        record["toUser"] = invite.fromUser
        record["fromUser"] = me
        record["fromName"] = name
        record["accepted"] = accept ? 1 : 0
        record["createdAt"] = Date.now
        record["title"] = accept ? "Invite Accepted" : "Invite Declined"
        record["body"] = accept ? "\(name) joined your circle on WithU." : "\(name) declined your invite."
        do {
            _ = try await database.save(record)
            answeredInvites.insert(invite.id)
            incomingInvites.removeAll { $0.id == invite.id }
        } catch {
            problem = error.localizedDescription
        }
    }

    // MARK: Following

    /// Tells the traveller you're responding to their alert.
    func sendOnIt(to trip: FollowedTrip) async {
        guard isAvailable, let me = myUserID else { return }
        respondedSOS.insert(trip.sosKey)
        let name = myName()
        let record = CKRecord(recordType: Schema.onIt)
        record["toUser"] = trip.fromUser
        record["fromUser"] = me
        record["fromName"] = name
        record["createdAt"] = Date.now
        record["title"] = "\(name) Is On It"
        record["body"] = "They're responding to your alert."
        _ = try? await database.save(record)
    }

    // MARK: CircleSyncing

    @discardableResult
    func send(_ message: CircleMessage) async -> Set<UUID> {
        let reachable = message.contactIDs.compactMap(contactLookup).filter(\.isConnected)
        guard isAvailable, let me = myUserID, !reachable.isEmpty else { return [] }
        let recipients = reachable.compactMap { $0.link?.remoteUserID }
        let name = myName()

        var type = Schema.tripEvent
        var kind = ""
        var title = ""
        var body = ""
        var snapshot: LocationSnapshot?
        var endsAt: Date?

        switch message.kind {
        case .tripStarted(let end):
            tripStartedAt = .now
            handledOnIt = []
            kind = "started"
            endsAt = end
            title = "\(name) Started a Trip"
            body = currentDestination().map { "Heading to \($0). You can follow along until they arrive." }
                ?? "You can follow along until they arrive."
        case .tripExtended(let end):
            type = Schema.tripUpdate
            kind = "extended"
            endsAt = end
        case .location(let snap):
            type = Schema.tripUpdate
            kind = "location"
            snapshot = snap
        case .checkInMissed:
            kind = "missed"
            title = "\(name) Missed a Check-In"
            body = "We're checking on them now."
        case .alert(let snap):
            kind = "alert"
            snapshot = snap
            title = "\(name) Needs Help"
            body = "They didn't answer a check-in. Open WithU to see where they are."
            startPollingForResponses(me: me)
        case .allClear:
            kind = "safe"
            title = "\(name) Is Safe"
            body = "They cancelled the alert."
            stopPollingForResponses()
        case .arrived:
            kind = "arrived"
            title = "\(name) Arrived"
            body = "They reached their destination. Sharing has stopped."
            stopPollingForResponses()
        case .tripCancelled:
            kind = "ended"
            title = "\(name) Ended Their Trip"
            body = "Location sharing has stopped."
            stopPollingForResponses()
        }

        let record = CKRecord(recordType: type)
        record["fromUser"] = me
        record["fromName"] = name
        record["recipients"] = recipients
        record["kind"] = kind
        record["createdAt"] = Date.now
        record["destination"] = currentDestination()
        record["fromPhone"] = myPhone()
        if !title.isEmpty {
            record["title"] = title
            record["body"] = body
        }
        if let endsAt { record["endsAt"] = endsAt }
        if let snapshot {
            record["latitude"] = snapshot.latitude
            record["longitude"] = snapshot.longitude
            record["battery"] = snapshot.batteryLevel
        }
        do {
            _ = try await database.save(record)
            return Set(reachable.map(\.id))
        } catch {
            problem = error.localizedDescription
            return []
        }
    }

    // MARK: - Private

    private func refreshIncomingInvites() async {
        guard let phone = myPhone(), let hash = Self.phoneHash(phone) else { return }
        let predicate = NSPredicate(format: "toPhoneHash == %@", hash)
        let answered = answeredInvites
        let records = await fetch(Schema.invite, predicate: predicate, limit: 20)
        incomingInvites = records.compactMap { record in
            let id = record.recordID.recordName
            guard !answered.contains(id),
                  let fromUser = record["fromUser"] as? String,
                  fromUser != myUserID else { return nil }
            return IncomingInvite(id: id,
                                  fromUser: fromUser,
                                  fromName: record["fromName"] as? String ?? "Someone",
                                  circleName: record["circleName"] as? String ?? "",
                                  sentAt: record["createdAt"] as? Date ?? .now)
        }
    }

    private func refreshInviteReplies(me: String) async {
        let records = await fetch(Schema.inviteReply, predicate: NSPredicate(format: "toUser == %@", me), limit: 100)
        // Oldest first, so a later answer wins.
        for record in records.reversed() {
            guard let inviteID = record["inviteID"] as? String,
                  let from = record["fromUser"] as? String else { continue }
            applyInviteReply(inviteID, from, (record["accepted"] as? Int64 ?? 0) == 1)
        }
    }

    private func refreshFollowing(me: String) async {
        let since = Date.now.addingTimeInterval(-12 * 3600)
        let predicate = NSPredicate(format: "recipients CONTAINS %@ AND createdAt > %@", me, since as NSDate)
        let events = await fetch(Schema.tripEvent, predicate: predicate, limit: 100)
        let updates = await fetch(Schema.tripUpdate, predicate: predicate, limit: 200)

        var trips: [String: FollowedTrip] = [:]
        // Events decide the state; newest first, so the first seen per person wins.
        for record in events {
            guard let from = record["fromUser"] as? String, trips[from] == nil else { continue }
            let state: FollowedTrip.State = switch record["kind"] as? String {
            case "alert", "missed": .needsHelp
            case "safe": .safe
            case "arrived": .arrived
            case "ended": .ended
            default: .onTheWay
            }
            trips[from] = FollowedTrip(fromUser: from,
                                       name: record["fromName"] as? String ?? "Someone",
                                       destination: record["destination"] as? String,
                                       state: state,
                                       endsAt: record["endsAt"] as? Date,
                                       latitude: record["latitude"] as? Double,
                                       longitude: record["longitude"] as? Double,
                                       battery: record["battery"] as? Double,
                                       updatedAt: record["createdAt"] as? Date ?? .now,
                                       stateSince: record["createdAt"] as? Date ?? .now,
                                       phone: record["fromPhone"] as? String)
        }
        // Quiet updates refresh the location and the timer.
        for record in updates {
            guard let from = record["fromUser"] as? String, var trip = trips[from],
                  let date = record["createdAt"] as? Date, date > trip.updatedAt else { continue }
            if let lat = record["latitude"] as? Double, let lon = record["longitude"] as? Double {
                trip.latitude = lat
                trip.longitude = lon
                trip.battery = record["battery"] as? Double ?? trip.battery
            }
            if let end = record["endsAt"] as? Date { trip.endsAt = end }
            trip.updatedAt = date
            trips[from] = trip
        }
        following = trips.values
            .filter { $0.isActive || Date.now.timeIntervalSince($0.updatedAt) < 3600 }
            .sorted { lhs, rhs in
                if (lhs.state == .needsHelp) != (rhs.state == .needsHelp) { return lhs.state == .needsHelp }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func refreshResponses(me: String) async {
        guard tripStartedAt > .distantPast else { return }
        let predicate = NSPredicate(format: "toUser == %@ AND createdAt > %@", me, tripStartedAt as NSDate)
        for record in await fetch(Schema.onIt, predicate: predicate, limit: 20) {
            let id = record.recordID.recordName
            guard !handledOnIt.contains(id),
                  let from = record["fromUser"] as? String,
                  let contact = contactForRemoteUser(from) else { continue }
            handledOnIt.insert(id)
            onContactResponse?(contact.id)
        }
    }

    /// While an alert runs, check for "On It" every 10 seconds in case a push is delayed.
    private func startPollingForResponses(me: String) {
        responsePoll?.cancel()
        responsePoll = Task { [weak self] in
            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                await self.refreshResponses(me: me)
            }
        }
    }

    private func stopPollingForResponses() {
        responsePoll?.cancel()
        responsePoll = nil
    }

    private func fetch(_ type: String, predicate: NSPredicate, limit: Int) async -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: limit)
            return results.compactMap { try? $0.1.get() }
        } catch {
            problem = error.localizedDescription
            return []
        }
    }

    /// Push notifications for new invites, replies, trip events and responses.
    private func saveSubscriptions() async {
        guard let me = myUserID else { return }
        var subscriptions: [(String, String, NSPredicate)] = [
            ("withu-replies", Schema.inviteReply, NSPredicate(format: "toUser == %@", me)),
            ("withu-trips", Schema.tripEvent, NSPredicate(format: "recipients CONTAINS %@", me)),
            ("withu-onit", Schema.onIt, NSPredicate(format: "toUser == %@", me))
        ]
        if let phone = myPhone(), let hash = Self.phoneHash(phone) {
            subscriptions.append(("withu-invites", Schema.invite, NSPredicate(format: "toPhoneHash == %@", hash)))
        }
        for (id, type, predicate) in subscriptions {
            let subscription = CKQuerySubscription(recordType: type,
                                                   predicate: predicate,
                                                   subscriptionID: id,
                                                   options: [.firesOnRecordCreation])
            let info = CKSubscription.NotificationInfo()
            info.titleLocalizationKey = "%1$@"
            info.titleLocalizationArgs = ["title"]
            info.alertLocalizationKey = "%1$@"
            info.alertLocalizationArgs = ["body"]
            info.soundName = "default"
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try? await database.save(subscription)
        }
    }

    /// Matches numbers however they're written: the last nine digits, hashed.
    nonisolated static func phoneHash(_ phone: String) -> String? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        let key = String(digits.suffix(9))
        return SHA256.hash(data: Data("withu-phone:\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
