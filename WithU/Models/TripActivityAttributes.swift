//
//  TripActivityAttributes.swift
//  WithU
//
//  Shared between the app and the widget extension. ActivityKit matches the
//  attributes by type name, so this file is compiled into both targets.
//

import ActivityKit
import Foundation

nonisolated struct TripActivityAttributes: ActivityAttributes {
    nonisolated enum Status: String, Codable, Hashable {
        case onTheWay
        case checkIn
        case alerting
        case arrived
    }

    nonisolated struct ContentState: Codable, Hashable {
        /// When the trip timer runs out.
        var endDate: Date
        var status: Status
        var remainingDistanceMeters: Double?
    }

    var destinationName: String
    var travelModeSymbol: String
    var contactInitials: [String]
    var startDate: Date
}
