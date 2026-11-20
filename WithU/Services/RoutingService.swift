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
    /// For a ride: the station where you get on and the one where you get off.
    var fromName: String?
    var toName: String?
    /// How long this leg takes, when known.
    var travelTime: TimeInterval?
    /// For a ride: "metro", "train" or "bus".
    var vehicle: String?

    init(kind: Kind,
         coordinates: [CLLocationCoordinate2D],
         fromName: String? = nil,
         toName: String? = nil,
         travelTime: TimeInterval? = nil,
         vehicle: String? = nil) {
        self.kind = kind
        self.points = coordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
        self.fromName = fromName
        self.toName = toName
        self.travelTime = travelTime
        self.vehicle = vehicle
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

    /// Apple Maps gives apps the transit arrival time, but not the line or the
    /// track. So we don't draw a track we can't be sure of. Instead the trip is
    /// three plain steps: walk to the station where you get on, ride, get off
    /// at the station nearest the destination, walk the rest. Only the walks
    /// are drawn. Exact lines and changes are one tap away in Apple Maps.
    private func transitRoute(from origin: CLLocationCoordinate2D,
                              to destination: Destination,
                              request: MKDirections.Request) async throws -> RouteResult {
        let eta = try await MKDirections(request: request).calculateETA()

        guard let pair = await stationPair(from: origin, to: destination.coordinate) else {
            // No stations within walking distance at one of the ends.
            return RouteResult(expectedTravelTime: eta.expectedTravelTime,
                               distance: eta.distance,
                               coordinates: [],
                               isBusyRoute: false,
                               legs: [],
                               note: "No station within walking distance. See Lines in Maps.")
        }

        async let firstWalk = walk(from: origin, to: pair.on.location.coordinate)
        async let lastWalk = walk(from: pair.off.location.coordinate, to: destination.coordinate)
        let (walkIn, walkOut) = await (firstWalk, lastWalk)
        let rideTime = max(eta.expectedTravelTime - walkIn.time - walkOut.time, 60)

        let legs = [
            RouteLeg(kind: .walk, coordinates: walkIn.path, toName: pair.on.name, travelTime: walkIn.time),
            // Only the two stations are kept: the track between them isn't drawn.
            RouteLeg(kind: .ride,
                     coordinates: [pair.on.location.coordinate, pair.off.location.coordinate],
                     fromName: pair.on.name,
                     toName: pair.off.name,
                     travelTime: rideTime,
                     vehicle: pair.vehicle),
            RouteLeg(kind: .walk, coordinates: walkOut.path, fromName: pair.off.name, toName: destination.name, travelTime: walkOut.time)
        ]
        return RouteResult(expectedTravelTime: eta.expectedTravelTime,
                           distance: eta.distance,
                           coordinates: [],
                           isBusyRoute: false,
                           legs: legs,
                           note: "Get on at \(pair.on.name), get off at \(pair.off.name)")
    }

    private struct Station {
        var name: String
        var location: CLLocation
    }

    private struct StationPair {
        var on: Station
        var off: Station
        var vehicle: String
    }

    /// Farthest we ask someone to walk to or from a station (about 15 minutes).
    private static let maxStationWalk: CLLocationDistance = 1200

    /// The station to get on at and the one to get off at, both of the same
    /// kind. Metro first, then train, then bus or tram stops. Within a kind,
    /// the pair with the least walking in total.
    private func stationPair(from origin: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async -> StationPair? {
        async let metroOn = stations(matching: ["stazione metropolitana", "metro station"], near: origin)
        async let metroOff = stations(matching: ["stazione metropolitana", "metro station"], near: end)
        if let pair = bestPair(await metroOn, await metroOff, origin: origin, end: end, vehicle: "metro") {
            return pair
        }
        async let trainOn = stations(matching: ["stazione ferroviaria", "train station"], near: origin)
        async let trainOff = stations(matching: ["stazione ferroviaria", "train station"], near: end)
        if let pair = bestPair(await trainOn, await trainOff, origin: origin, end: end, vehicle: "train") {
            return pair
        }
        async let stopsOn = transportStops(near: origin)
        async let stopsOff = transportStops(near: end)
        return bestPair(await stopsOn, await stopsOff, origin: origin, end: end, vehicle: "bus")
    }

    private func bestPair(_ onCandidates: [Station], _ offCandidates: [Station],
                          origin: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
                          vehicle: String) -> StationPair? {
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let finish = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let ons = onCandidates.filter { $0.location.distance(from: start) <= Self.maxStationWalk }
        let offs = offCandidates.filter { $0.location.distance(from: finish) <= Self.maxStationWalk }
        var best: (pair: StationPair, walking: CLLocationDistance)?
        for on in ons {
            for off in offs where on.name != off.name && on.location.distance(from: off.location) > 300 {
                let walking = on.location.distance(from: start) + off.location.distance(from: finish)
                if best == nil || walking < best!.walking {
                    best = (StationPair(on: on, off: off, vehicle: vehicle), walking)
                }
            }
        }
        return best?.pair
    }

    /// Stations found by name (Apple Maps' "public transport" category is
    /// mostly bus stops, so metro and train stations are searched by name).
    private func stations(matching queries: [String], near coordinate: CLLocationCoordinate2D) async -> [Station] {
        var found: [Station] = []
        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: coordinate,
                                                latitudinalMeters: Self.maxStationWalk * 2,
                                                longitudinalMeters: Self.maxStationWalk * 2)
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            for item in items {
                let station = Station(name: item.name ?? "Station", location: item.location)
                if !found.contains(where: { $0.name == station.name }) { found.append(station) }
            }
        }
        return found
    }

    /// Any bus, tram or other stop nearby, as a last resort.
    private func transportStops(near coordinate: CLLocationCoordinate2D) async -> [Station] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: Self.maxStationWalk)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        return items.map { Station(name: $0.name ?? "Stop", location: $0.location) }
    }

    /// The real walking path and time, or a straight line at walking pace.
    private func walk(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async -> (path: [CLLocationCoordinate2D], time: TimeInterval) {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .walking
        if let route = try? await MKDirections(request: request).calculate().routes.first {
            return (route.polyline.coordinates, route.expectedTravelTime)
        }
        let meters = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        return ([start, end], meters / 1.3)
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
