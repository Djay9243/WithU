//
//  RouteLines.swift
//  WithU
//
//  Draws a route on any Map. For public transport only the walks are drawn,
//  with a pin where you get on and where you get off: Apple Maps doesn't
//  give apps the track, so we don't guess one.
//

import MapKit
import SwiftUI

struct RouteLines: MapContent {
    var legs: [RouteLeg]

    var body: some MapContent {
        ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
            // The ride between stations isn't drawn: the track is unknown.
            if leg.kind != .ride, leg.points.count > 1 {
                // One simple solid line with a white edge, like Apple Maps.
                MapPolyline(coordinates: leg.coordinates)
                    .stroke(.white, style: leg.kind.casingStyle)
                MapPolyline(coordinates: leg.coordinates)
                    .stroke(leg.kind.color, style: leg.kind.strokeStyle)
            }
        }
        ForEach(Array(stations.enumerated()), id: \.offset) { _, station in
            Marker(station.label, systemImage: station.symbol, coordinate: station.coordinate)
                .tint(TravelMode.transit.routeColor)
        }
    }

    private var stations: [(label: String, symbol: String, coordinate: CLLocationCoordinate2D)] {
        legs.filter { $0.kind == .ride }.flatMap { leg -> [(label: String, symbol: String, coordinate: CLLocationCoordinate2D)] in
            let points = leg.coordinates
            guard let first = points.first, let last = points.last else { return [] }
            let symbol = TransitVehicle.symbol(leg.vehicle)
            var result: [(label: String, symbol: String, coordinate: CLLocationCoordinate2D)] = []
            if let from = leg.fromName { result.append(("Get on: \(from)", symbol, first)) }
            if let to = leg.toName { result.append(("Get off: \(to)", symbol, last)) }
            return result
        }
    }
}

/// Words and symbols for the kind of public transport.
enum TransitVehicle {
    static func symbol(_ vehicle: String?) -> String {
        switch vehicle {
        case "train": "train.side.front.car"
        case "bus": "bus.fill"
        default: "tram.fill"
        }
    }

    static func name(_ vehicle: String?) -> String {
        switch vehicle {
        case "train": "train"
        case "bus": "bus"
        default: "metro"
        }
    }
}

/// A public transport trip as plain steps:
/// walk to the station, ride and get off at the right stop, walk the rest.
struct TransitSteps: View {
    var legs: [RouteLeg]
    var destinationName: String
    var compact = false

    var body: some View {
        if let ride = legs.first(where: { $0.kind == .ride }),
           let on = ride.fromName, let off = ride.toName {
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                let walkIn = legs.first { $0.kind == .walk && $0.toName == on }
                let walkOut = legs.last { $0.kind == .walk && $0.fromName == off }
                // Names go in as Text values, so characters like * or _ in a
                // place name are never read as formatting.
                step(symbol: "figure.walk",
                     text: Text("Walk\(minutes(walkIn)) to \(Text(on).bold())"))
                step(symbol: TransitVehicle.symbol(ride.vehicle),
                     text: Text("Take the \(TransitVehicle.name(ride.vehicle)), get off at \(Text(off).bold())"))
                if !compact {
                    step(symbol: "figure.walk",
                         text: Text("Walk\(minutes(walkOut)) to \(destinationName)"))
                }
            }
            .font(compact ? .caption : .footnote)
            .foregroundStyle(Theme.ink)
            .accessibilityElement(children: .combine)
        }
    }

    private func step(symbol: String, text: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(TravelMode.transit.routeColor)
                .frame(width: 18)
                .accessibilityHidden(true)
            text
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func minutes(_ leg: RouteLeg?) -> String {
        guard let time = leg?.travelTime else { return "" }
        return " \(Format.duration(max(time, 60)))"
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

    /// Every route is a plain solid line (no dots or dashes); only the
    /// colour and thickness say how you travel.
    var lineWidth: CGFloat {
        switch self {
        case .walk: 5
        case .cycle, .ride: 6
        case .drive: 7
        }
    }

    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    /// The white edge drawn underneath so the line stands out on the map.
    var casingStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth + 3, lineCap: .round, lineJoin: .round)
    }
}
