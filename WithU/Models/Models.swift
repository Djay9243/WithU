//
//  Models.swift
//  WithU
//
//  Core value types shared across the app. Everything here is `nonisolated`
//  so it can be encoded, decoded and passed between tasks freely.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Travel mode

/// How the person is travelling. Drives the Apple Maps ETA request, the arrival
/// radius and the thresholds used by smart check-ins.
nonisolated enum TravelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case walk, drive, cycle, transit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: "Walk"
        case .drive: "Drive"
        case .cycle: "Cycle"
        case .transit: "Transit"
        }
    }

    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .drive: "car.fill"
        case .cycle: "bicycle"
        case .transit: "tram.fill"
        }
    }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .walk: .walking
        case .drive: .automobile
        case .cycle: .cycling
        case .transit: .transit
        }
    }

    /// Distance from the destination at which the trip counts as arrived.
    var arrivalRadius: CLLocationDistance {
        switch self {
        case .walk: 50
        case .cycle: 75
        case .drive, .transit: 120
        }
    }

    /// Sustained speed (m/s) above this means the person is probably not
    /// travelling the way they said, e.g. a walking trip that is suddenly in a car.
    var unexpectedSpeed: CLLocationSpeed? {
        switch self {
        case .walk: 6
        case .cycle: 14
        case .drive, .transit: nil
        }
    }

    /// How far from the planned route someone can drift before we ask if they are okay.
    var offRouteTolerance: CLLocationDistance {
        switch self {
        case .walk: 120
        case .cycle: 200
        case .drive: 300
        case .transit: 450
        }
    }


    var liveUpdateConfiguration: CLLocationUpdate.LiveConfiguration {
        switch self {
        case .drive: .automotiveNavigation
        case .walk, .cycle, .transit: .otherNavigation
        }
    }
}

// MARK: - Destination

nonisolated struct Destination: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(latitude),\(longitude),\(name)" }
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// A label for a place the person goes often, one place per label.
nonisolated enum PlaceTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, work, gym

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .work: "Work"
        case .gym: "Gym"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .gym: "dumbbell.fill"
        }
    }
}

nonisolated struct SavedPlace: Codable, Hashable, Sendable, Identifiable {
    var tag: PlaceTag
    var destination: Destination
    var id: PlaceTag { tag }
}

// MARK: - Contacts

/// Whether a contact has accepted your invite on their own copy of WithU.
nonisolated struct ContactLink: Codable, Hashable, Sendable {
    nonisolated enum Status: String, Codable, Sendable {
        case invited, connected, declined
    }
    var status: Status
    /// The invite record sent to them.
    var inviteID: String?
    /// Their iCloud user, known once they accept.
    var remoteUserID: String?
}

nonisolated struct TrustedContact: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var phoneNumber: String?
    /// Kept for settings saved by older builds.
    var hasApp: Bool = true
    var colorIndex: Int = 0
    /// Invite state. Only connected contacts receive trips, location and alerts.
    var link: ContactLink?

    var isConnected: Bool { link?.status == .connected && link?.remoteUserID != nil }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
}

/// A named group of trusted contacts, e.g. "Family" or "Flatmates". A trip is
/// shared with exactly one circle.
nonisolated struct TrustedCircle: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var contacts: [TrustedContact] = []
    /// Optional so circles saved by older builds still decode.
    var storiesSetting: Bool?

    /// Whether this circle can be picked as an audience for stories. Turn it
    /// off for a "safety only" circle that gets alerts but never photos.
    var receivesStories: Bool {
        get { storiesSetting ?? true }
        set { storiesSetting = newValue }
    }

    static let defaultName = "My Circle"
}

/// A person from the system address book who is not yet in the circle.
nonisolated struct ContactCandidate: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var phoneNumber: String?
}

// MARK: - Trip plan

nonisolated struct TripPlan: Codable, Hashable, Sendable {
    var destination: Destination
    var mode: TravelMode
    var expectedTravelTime: TimeInterval
    var distance: CLLocationDistance
    var checkOnStop: Bool
    var stopThresholdMinutes: Int
    var deadline: Date?
}

// MARK: - Saved trip

/// The active trip, written to disk so it survives the app being closed and
/// can be resumed from a notification or the Live Activity.
nonisolated struct SavedTrip: Codable, Sendable {
    nonisolated struct Point: Codable, Sendable {
        var latitude: Double
        var longitude: Double
    }

    var plan: TripPlan
    var circle: TrustedCircle
    var startedAt: Date
    var endsAt: Date
    var route: [Point]
    var isBusyRoute: Bool
    var extensionsAdded: TimeInterval
    var isAlerting: Bool
    var alertStartedAt: Date?
    /// Links stories to the trip. Optional for trips saved by older builds.
    var tripID: UUID?
    /// What's drawn on the map. Optional for trips saved by older builds.
    var legs: [RouteLeg]?
    /// An SOS without a planned trip. Optional for trips saved by older builds.
    var isSOSOnly: Bool?
    /// A check-in waiting for a reply, so the countdown survives the app closing.
    var pendingCheckIn: PendingCheckIn?
    /// When the long-stop check-in comes back after "Remind Me Later".
    var stopReminderAt: Date?

    nonisolated struct PendingCheckIn: Codable, Sendable {
        var reason: CheckInReason
        var deadline: Date
        var isFollowUp: Bool
    }
}

// MARK: - Check-ins and alerts

nonisolated enum CheckInReason: String, Codable, Sendable, Hashable {
    case unusualStop
    case offRoute
    case unexpectedSpeed
    case timerExpired
    case deadlinePassed
    case manual

    var title: String {
        switch self {
        case .unusualStop: "You've stopped for a bit"
        case .offRoute: "Taking a different way?"
        case .unexpectedSpeed: "Picked up some speed?"
        case .timerExpired: "Taking a little longer?"
        case .deadlinePassed: "Not home yet?"
        case .manual: "Just checking in"
        }
    }

    var message: String {
        switch self {
        case .unusualStop: "Share a moment with your circle, or carry on when you're ready."
        case .offRoute: "Looks like you went a different way. That's okay, just let us know you're fine."
        case .unexpectedSpeed: "You're moving faster than usual. Hopped on a bus or taxi? Let us know you're fine."
        case .timerExpired: "No worries. Add a few minutes, or let us know you're fine."
        case .deadlinePassed: "You asked us to check in around now. Let us know you're fine."
        case .manual: "Let your circle know you're fine."
        }
    }
}

nonisolated enum ContactAlertStatus: String, Codable, Sendable, Hashable {
    case notYetNotified
    case notified
    case delivered
    case noResponse
    case onIt
    case unreachable

    var label: String {
        switch self {
        case .notYetNotified: "Waiting"
        case .notified: "Sending…"
        case .delivered: "Alerted"
        case .noResponse: "No Reply Yet"
        case .onIt: "On It"
        case .unreachable: "Not on WithU Yet"
        }
    }
}

nonisolated struct ContactAlertState: Identifiable, Hashable, Sendable {
    var contact: TrustedContact
    var status: ContactAlertStatus
    var id: UUID { contact.id }
}

/// What gets shared with contacts when an alert starts: the last place the
/// phone was detected, when that was, and the battery.
nonisolated struct LocationSnapshot: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    /// 0...1, or nil when the phone can't tell (e.g. the Simulator).
    var batteryLevel: Double?
    /// When the location was detected, not when the alert was sent.
    var timestamp: Date
    /// False when no location was detected at all during the trip.
    var hasLocation: Bool = true
}

// MARK: - Settings

nonisolated struct AppSettings: Codable, Equatable, Sendable {
    var userName: String = ""
    var lowBatteryPing = true
    var preferBusyRoute = true
    var checkOnStop = true
    var stopThresholdMinutes = 15
    var homeDeadlineEnabled = false
    /// Minutes since midnight, default 22:45.
    var homeDeadlineMinutes = 22 * 60 + 45
    var lastTravelMode: TravelMode = .walk
    /// The circle trips are shared with until the person picks another.
    var selectedCircleID: UUID?
    // Stored as optionals so settings saved by older builds still decode.
    var appearanceChoice: AppearanceMode?
    var checkInResponseChoice: Int?
    /// From your own contact card; used so people can invite you.
    var userPhone: String?

    /// How long you have to answer a check-in before your circle is alerted.
    /// Older builds stored 1–5 minutes; those fall back to the new default.
    var checkInResponseSeconds: Int {
        get {
            guard let choice = checkInResponseChoice,
                  TripRules.checkInWindowOptions.contains(choice) else { return TripRules.defaultCheckInWindow }
            return choice
        }
        set { checkInResponseChoice = newValue }
    }

    var appearance: AppearanceMode {
        get { appearanceChoice ?? .system }
        set { appearanceChoice = newValue }
    }

    /// The next occurrence of the configured deadline time.
    func nextHomeDeadline(after date: Date = .now, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        var candidate = start.addingTimeInterval(TimeInterval(homeDeadlineMinutes * 60))
        if candidate <= date {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}

// MARK: - Trip rules

/// Tunable constants for the safety logic, kept in one place.
nonisolated enum TripRules {
    /// Default seconds to answer a check-in before the whole circle is alerted.
    static let defaultCheckInWindow = 15 * 60
    /// Choices offered in Settings: 15 or 20 minutes.
    static let checkInWindowOptions = [15 * 60, 20 * 60]
    /// A gentle reminder notification this long before the circle is alerted.
    static let checkInReminderLead: TimeInterval = 5 * 60
    /// "Remind Me Later" on a long-stop check-in asks again after this long.
    static let stopReminderDelay: TimeInterval = 15 * 60
    /// Default extension when running late.
    static let extensionStep: TimeInterval = 10 * 60
    /// A location fix older than this means we are waiting for signal.
    static let staleFixAge: TimeInterval = 90
    /// Movement under this distance counts as standing still.
    static let stillRadius: CLLocationDistance = 40
    /// How many consecutive anomalous fixes before we ask.
    static let strikesBeforeCheckIn = 3
    /// After an "I'm OK", ignore the same reason for this long.
    static let reasonCooldown: TimeInterval = 5 * 60
    /// Battery fraction that triggers the low-battery location ping.
    static let lowBatteryLevel: Double = 0.05
}
