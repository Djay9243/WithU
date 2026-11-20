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
    /// Empty for transit, where Apple Maps only provides an arrival estimate.
    var coordinates: [CLLocationCoordinate2D]
    /// True when the chosen route was picked for being busier rather than fastest.
    var isBusyRoute: Bool
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
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
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

        if !mode.providesRoutePolyline {
            let eta = try await MKDirections(request: request).calculateETA()
            return RouteResult(expectedTravelTime: eta.expectedTravelTime,
                               distance: eta.distance,
                               coordinates: [],
                               isBusyRoute: false)
        }

        let response = try await MKDirections(request: request).calculate()
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

        return RouteResult(expectedTravelTime: chosen.expectedTravelTime,
                           distance: chosen.distance,
                           coordinates: chosen.polyline.coordinates,
                           isBusyRoute: isBusy)
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
