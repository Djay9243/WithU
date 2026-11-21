//
//  PlaceService.swift
//  WithU
//
//  Apple Maps lookups for stories: the places around you and the city you're in.
//

import CoreLocation
import MapKit

nonisolated enum PlaceService {
    /// Cafés, sights, parks and similar places within a short walk.
    static func nearbyPlaces(around location: CLLocation, radius: CLLocationDistance = 200) async -> [StoryPlace] {
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: interestingCategories)
        let city = await cityName(for: location)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let places = response.mapItems.compactMap { item -> StoryPlace? in
            guard let name = item.name else { return nil }
            let coordinate = item.location.coordinate
            return StoryPlace(name: name,
                              city: city,
                              latitude: coordinate.latitude,
                              longitude: coordinate.longitude,
                              symbol: symbol(for: item.pointOfInterestCategory))
        }
        // Closest first.
        return places.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: location)
        }
        .prefix(8)
        .map { $0 }
    }

    /// The city, e.g. "Naples", for city-only stories.
    static func cityName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let items = try? await request.mapItems else { return nil }
        return items.first?.addressRepresentations?.cityName
    }

    /// A spot tapped on the map, named from its street address when there is one.
    static func destination(at coordinate: CLLocationCoordinate2D) async -> Destination {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var name = "Dropped Pin"
        var subtitle = ""
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first {
            if let street = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)?
                .components(separatedBy: ",").first, !street.isEmpty {
                name = street
            } else if let itemName = item.name {
                name = itemName
            }
            subtitle = item.addressRepresentations?.cityName ?? ""
        }
        return Destination(name: name, subtitle: subtitle,
                           latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private static let interestingCategories: [MKPointOfInterestCategory] = [
        .cafe, .restaurant, .bakery, .museum, .park, .beach, .landmark, .nationalMonument,
        .castle, .fortress, .theater, .musicVenue, .nightlife, .store, .marina, .zoo,
        .aquarium, .amusementPark, .library, .university, .publicTransport, .hotel
    ]

    private static func symbol(for category: MKPointOfInterestCategory?) -> String {
        switch category {
        case .cafe: "cup.and.saucer.fill"
        case .restaurant, .bakery: "fork.knife"
        case .museum, .library: "building.columns.fill"
        case .park, .nationalMonument: "tree.fill"
        case .beach, .marina: "beach.umbrella.fill"
        case .landmark, .castle, .fortress: "star.fill"
        case .theater, .musicVenue, .nightlife: "music.note"
        case .store: "bag.fill"
        case .publicTransport: "tram.fill"
        case .hotel: "bed.double.fill"
        default: "mappin"
        }
    }
}
