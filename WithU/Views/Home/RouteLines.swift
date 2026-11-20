//
//  RouteLines.swift
//  WithU
//
//  Draws a route on any Map, with a different line for each way of
//  travelling so they're easy to tell apart (like Apple Maps):
//  walking dotted, cycling and driving solid, the metro/train ride dashed
//  with a station pin at each end.
//

import MapKit
import SwiftUI

struct RouteLines: MapContent {
    var legs: [RouteLeg]

    var body: some MapContent {
        ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
            if leg.points.count > 1 {
                MapPolyline(coordinates: leg.coordinates)
                    .stroke(leg.kind.color, style: leg.kind.strokeStyle)
            }
        }
        ForEach(Array(stations.enumerated()), id: \.offset) { _, station in
            Marker(station.name, systemImage: "tram.fill", coordinate: station.coordinate)
                .tint(TravelMode.transit.routeColor)
        }
    }

    private var stations: [(name: String, coordinate: CLLocationCoordinate2D)] {
        legs.filter { $0.kind == .ride }.flatMap { leg -> [(name: String, coordinate: CLLocationCoordinate2D)] in
            let points = leg.coordinates
            guard let first = points.first, let last = points.last else { return [] }
            var result: [(name: String, coordinate: CLLocationCoordinate2D)] = []
            if let from = leg.fromName { result.append((from, first)) }
            if let to = leg.toName { result.append((to, last)) }
            return result
        }
    }
}

extension RouteLeg.Kind {
    var color: Color {
        switch self {
        case .walk: TravelMode.walk.routeColor
        case .cycle: TravelMode.cycle.routeColor
        case .drive: TravelMode.drive.routeColor
        case .ride: TravelMode.transit.routeColor
        }
    }

    var strokeStyle: StrokeStyle {
        switch self {
        case .walk:
            // Round dots.
            StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round, dash: [0.1, 12])
        case .cycle:
            StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        case .drive:
            StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
        case .ride:
            StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: [14, 10])
        }
    }
}
