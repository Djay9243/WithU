//
//  RoutingService.swift
//  WithU
//
//  Destination search, Apple Maps arrival estimates and the "busy route"
//  preference that favours walking routes passing more shops, cafés and stations.
//

import Foundation
import MapKit

nonisolated struct RouteResult: Sendable {
    var expectedTravelTime: TimeInterval
    var distance: CLLocationDistance
    /// The path used for off-route checks. Empty for transit: Apple Maps
    /// doesn't share the metro line's shape, so we can't check it.
    var coordinates: [CLLocationCoordinate2D]
    /// True when the chosen route was picked for being busier rather than fastest.
    var isBusyRoute: Bool
    /// What's drawn on the map, leg by leg (walk to the station, ride, walk).
    var legs: [RouteLeg] = []
    /// A short note shown under the time, e.g. which stations to use.
    var note: String? = nil
}

/// One drawn part of a route. Each kind has its own line style, like Apple Maps:
/// walking dotted, cycling and driving solid, the metro/train ride dashed.
nonisolated struct RouteLeg: Codable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case walk, cycle, drive, ride
    }
    var kind: Kind
    var points: [SavedTrip.Point]
    /// For a ride: the station names at each end.
    var fromName: String?
    var toName: String?

    init(kind: Kind, coordinates: [CLLocationCoordinate2D], fromName: String? = nil, toName: String? = nil) {
        self.kind = kind
        self.points = coordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
        self.fromName = fromName
        self.toName = toName
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

/// WithU is available for trips in Italy only.
nonisolated enum Italy {
    /// Covers mainland Italy, Sicily and Sardinia.
    static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.8, longitude: 12.6),
        span: MKCoordinateSpan(latitudeDelta: 12.2, longitudeDelta: 12.4)
    )

    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (35.4...47.1).contains(coordinate.latitude) && (6.6...18.6).contains(coordinate.longitude)
    }

    /// Uses the address country when known, otherwise the coordinate.
    static func contains(_ item: MKMapItem) -> Bool {
        if let region = item.addressRepresentations?.region {
            return region.identifier == "IT"
        }
        return contains(item.location.coordinate)
    }
}

final class RoutingService {
    enum RoutingError: LocalizedError {
        case noRoute
        var errorDescription: String? { "Apple Maps couldn't find a route." }
    }

    /// Searches places and addresses near the person.
    func search(_ query: String, near center: CLLocationCoordinate2D?) async throws -> [Destination] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]
        // Search near the person when they're in Italy, otherwise across Italy.
        if let center, Italy.contains(center) {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        } else {
            request.region = Italy.region
        }
        request.regionPriority = .required
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.filter(Italy.contains).map { item in
            let location = item.location
            let name = item.name ?? item.address?.shortAddress ?? "Dropped pin"
            let subtitle = item.address?.shortAddress
                ?? item.addressRepresentations?.cityWithContext
                ?? ""
            return Destination(
                name: name,
                subtitle: subtitle == name ? "" : subtitle,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    /// Returns travel time, distance and a drawable route for the trip.
    func route(from origin: CLLocationCoordinate2D,
               to destination: Destination,
               mode: TravelMode,
               preferBusy: Bool) async throws -> RouteResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: destination.location, address: nil)
        request.transportType = mode.transportType
        request.requestsAlternateRoutes = preferBusy && mode == .walk

        if mode == .transit {
            return try await transitRoute(from: origin, to: destination, request: request)
        }

        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch where mode == .cycle {
            // Apple Maps has cycling directions only in some cities. Fall back
            // to the walking path with a cycling time instead of an error.
            return try await cyclingFallback(from: origin, to: destination)
        }
        guard let fastest = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            throw RoutingError.noRoute
        }

        var chosen = fastest
        var isBusy = false
        if preferBusy, mode == .walk, response.routes.count > 1 {
            if let busier = await busiestRoute(among: response.routes, fastest: fastest), busier !== fastest {
                chosen = busier
                isBusy = true
            }
        }

        let path = chosen.polyline.coordinates
        return RouteResult(expectedTravelTime: chosen.expectedTravelTime,
                           distance: chosen.distance,
                           coordinates: path,
                           isBusyRoute: isBusy,
                           legs: [RouteLeg(kind: mode.legKind, coordinates: path)])
    }

    // MARK: - Transit

    /// Apple Maps gives the transit arrival time but not the line's shape. So
    /// we draw what we can know: the real walk to the nearest station, the
    /// ride between stations (dashed, straight), and the walk at the end.
    /// Exact lines and changes are one tap away in Apple Maps.
    private func transitRoute(from origin: CLLocationCoordinate2D,
                              to destination: Destination,
                              request: MKDirections.Request) async throws -> RouteResult {
        let eta = try await MKDirections(request: request).calculateETA()
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        async let nearStart = nearestStation(to: origin)
        async let nearEnd = nearestStation(to: destination.coordinate)
        let (fromStation, toStation) = await (nearStart, nearEnd)

        var legs: [RouteLeg] = []
        var note: String?
        if let fromStation, let toStation,
           fromStation.name != toStation.name,
           fromStation.location.distance(from: toStation.location) > 300 {
            async let firstWalk = walkingPath(from: origin, to: fromStation.location.coordinate)
            async let lastWalk = walkingPath(from: toStation.location.coordinate, to: destination.coordinate)
            let (walkIn, walkOut) = await (firstWalk, lastWalk)
            legs = [
                RouteLeg(kind: .walk, coordinates: walkIn),
                RouteLeg(kind: .ride,
                         coordinates: [fromStation.location.coordinate, toStation.location.coordinate],
                         fromName: fromStation.name, toName: toStation.name),
                RouteLeg(kind: .walk, coordinates: walkOut)
            ]
            note = "From \(fromStation.name) to \(toStation.name)"
        } else {
            // No stations found nearby: show the trip as one dashed ride.
            legs = [RouteLeg(kind: .ride, coordinates: [start.coordinate, destination.coordinate])]
            note = "Public transport"
        }
        return RouteResult(expectedTravelTime: eta.expectedTravelTime,
                           distance: eta.distance,
                           coordinates: [],
                           isBusyRoute: false,
                           legs: legs,
                           note: note)
    }

    private struct Station {
        var name: String
        var location: CLLocation
    }

    /// The closest metro or train station within a 15-minute walk, else the
    /// closest stop. Apple Maps' "public transport" category is mostly bus
    /// stops, so metro and train stations are searched for by name first.
    private func nearestStation(to coordinate: CLLocationCoordinate2D) async -> Station? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let maxWalk: CLLocationDistance = 1200

        async let metro = stations(matching: "stazione metropolitana", near: coordinate)
        async let rail = stations(matching: "train station", near: coordinate)
        let railStations = await (metro + rail)
            .filter { $0.location.distance(from: here) <= maxWalk }
        if let nearest = railStations.min(by: { $0.location.distance(from: here) < $1.location.distance(from: here) }) {
            return nearest
        }

        // No metro or train nearby: the closest bus or tram stop.
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: maxWalk)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return nil }
        return items
            .map { Station(name: $0.name ?? "Stop", location: $0.location) }
            .min { $0.location.distance(from: here) < $1.location.distance(from: here) }
    }

    private func stations(matching query: String, near coordinate: CLLocationCoordinate2D) async -> [Station] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 2400, longitudinalMeters: 2400)
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        return items.map { Station(name: $0.name ?? "Station", location: $0.location) }
    }

    /// The real walking path, or a straight line if Apple Maps can't find one.
    private func walkingPath(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .walking
        if let route = try? await MKDirections(request: request).calculate().routes.first {
            return route.polyline.coordinates
        }
        return [start, end]
    }

    // MARK: - Cycling fallback

    private func cyclingFallback(from origin: CLLocationCoordinate2D, to destination: Destination) async throws -> RouteResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: destination.location, address: nil)
        request.transportType = .walking
        guard let route = try await MKDirections(request: request).calculate().routes.first else {
            throw RoutingError.noRoute
        }
        let path = route.polyline.coordinates
        let cyclingSpeed = 4.2 // m/s, about 15 km/h
        return RouteResult(expectedTravelTime: route.distance / cyclingSpeed,
                           distance: route.distance,
                           coordinates: path,
                           isBusyRoute: false,
                           legs: [RouteLeg(kind: .cycle, coordinates: path)],
                           note: "No bike lanes from Apple Maps here, so this follows streets")
    }

    /// Scores candidate routes by how many open-to-the-public places sit along
    /// them. Only routes within 30% of the fastest time are considered.
    private func busiestRoute(among routes: [MKRoute], fastest: MKRoute) async -> MKRoute? {
        let limit = fastest.expectedTravelTime * 1.3
        let candidates = routes.filter { $0.expectedTravelTime <= limit }
        guard candidates.count > 1 else { return nil }

        var scores: [(route: MKRoute, score: Double)] = []
        for route in candidates {
            scores.append((route, await busyScore(for: route)))
        }
        guard let best = scores.max(by: { $0.score < $1.score }),
              let fastestScore = scores.first(where: { $0.route === fastest })?.score else { return nil }
        // Only prefer a slower route when it is clearly busier.
        return best.score >= fastestScore * 1.25 + 0.5 ? best.route : fastest
    }

    private func busyScore(for route: MKRoute) async -> Double {
        let coordinates = route.polyline.coordinates
        guard !coordinates.isEmpty else { return 0 }
        let region = MKCoordinateRegion(route.polyline.boundingMapRect)
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .cafe, .restaurant, .store, .bakery, .pharmacy, .publicTransport, .hotel, .foodMarket
        ])
        guard let response = try? await MKLocalSearch(request: request).start() else { return 0 }
        let nearby = response.mapItems.filter { item in
            RouteGeometry.distance(from: item.location.coordinate, toPolyline: coordinates) <= 100
        }
        // Normalise by length so long routes don't win just by being long.
        let kilometres = max(route.distance / 1000, 0.2)
        return Double(nearby.count) / kilometres
    }
}

extension TravelMode {
    nonisolated var legKind: RouteLeg.Kind {
        switch self {
        case .walk: .walk
        case .cycle: .cycle
        case .drive: .drive
        case .transit: .ride
        }
    }
}

// MARK: - Geometry

nonisolated enum RouteGeometry {
    /// Shortest distance in metres from a coordinate to a polyline.
    static func distance(from coordinate: CLLocationCoordinate2D, toPolyline polyline: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard polyline.count > 1 else {
            if let only = polyline.first {
                return CLLocation(latitude: only.latitude, longitude: only.longitude)
                    .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }
            return .infinity
        }
        let point = MKMapPoint(coordinate)
        var best = Double.infinity
        for index in 0..<(polyline.count - 1) {
            let a = MKMapPoint(polyline[index])
            let b = MKMapPoint(polyline[index + 1])
            let projected = closestPoint(on: a, b, to: point)
            best = min(best, point.distance(to: projected))
        }
        return best
    }

    private static func closestPoint(on a: MKMapPoint, _ b: MKMapPoint, to p: MKMapPoint) -> MKMapPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return a }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        return MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
    }
}

extension MKPolyline {
    nonisolated var coordinates: [CLLocationCoordinate2D] {
        let buffer = UnsafeBufferPointer(start: points(), count: pointCount)
        return buffer.map(\.coordinate)
    }
}
