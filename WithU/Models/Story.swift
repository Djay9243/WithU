//
//  Story.swift
//  WithU
//
//  Stories are the moments a traveller shares during a trip: photos, a note
//  and where it happened. Journeys are the finished trips kept in the journal.
//

import CoreLocation
import Foundation

// MARK: - Location precision

/// How much of a story's location is shown to the people who see it.
nonisolated enum LocationPrecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case place, city, hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .place: "Place"
        case .city: "City Only"
        case .hidden: "No Location"
        }
    }

    var symbol: String {
        switch self {
        case .place: "mappin.and.ellipse"
        case .city: "building.2"
        case .hidden: "location.slash"
        }
    }
}

// MARK: - Audience

/// Who can see a story. Stories only ever go to people in your circles:
/// whole circles, chosen members of a circle, or nobody (only you).
nonisolated struct StoryAudience: Codable, Hashable, Sendable {
    var circleIDs: [UUID] = []
    /// Individual circle members, for sharing with only some people in a circle.
    var memberIDs: [UUID] = []

    static let onlyMe = StoryAudience()

    var isPrivate: Bool { circleIDs.isEmpty && memberIDs.isEmpty }
}

// MARK: - Story

nonisolated struct Story: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    /// The trip it was shared during, if any.
    var tripID: UUID?
    var caption: String
    /// File names in the story photo folder. Photos are saved without metadata.
    var photoFiles: [String]
    var placeName: String?
    var cityName: String?
    var latitude: Double?
    var longitude: Double?
    var precision: LocationPrecision
    var audience: StoryAudience
    /// When set, the story disappears after this date.
    var expiresAt: Date?

    /// The location text people see, respecting the chosen precision.
    var displayPlace: String? {
        switch precision {
        case .place: placeName ?? cityName
        case .city: cityName
        case .hidden: nil
        }
    }

    /// Only exact-place stories are pinned on maps.
    var mapCoordinate: CLLocationCoordinate2D? {
        guard precision == .place, let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func isExpired(at date: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }
}

// MARK: - Journey

/// A finished trip, kept in the journal. Only a summary is kept: the route
/// itself is still deleted when the trip ends.
nonisolated struct Journey: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var destinationName: String
    var mode: TravelMode
    var startedAt: Date
    var endedAt: Date
    var distance: CLLocationDistance
    var circleName: String

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}
