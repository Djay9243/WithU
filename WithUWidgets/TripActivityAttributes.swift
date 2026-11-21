//
//  TripActivityAttributes.swift
//  WithUWidgets
//
//  Mirror of the app's TripActivityAttributes. ActivityKit matches a Live
//  Activity to its UI by the attributes type name, so both targets compile
//  an identical definition. Keep this file in sync with
//  WithU/Models/TripActivityAttributes.swift.
//

import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case onTheWay
        case checkIn
        case alerting
        case arrived
    }

    struct ContentState: Codable, Hashable {
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
