//
//  Persistence.swift
//  WithU
//
//  Tiny JSON-in-UserDefaults store. No account, no server: everything lives
//  on the device (and in iCloud via the device backup).
//

import Foundation

nonisolated enum Persistence {
    enum Key: String {
        case onboardingComplete = "withu.onboarding.complete"
        case settings = "withu.settings"
        case contacts = "withu.contacts"
        case circles = "withu.circles"
        case activeTrip = "withu.activeTrip"
        case recentDestinations = "withu.recentDestinations"
        case savedPlaces = "withu.savedPlaces"
        case stories = "withu.stories"
        case journeys = "withu.journeys"
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key.rawValue)
    }

    static func remove(_ key: Key) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }

    static func bool(for key: Key) -> Bool {
        UserDefaults.standard.bool(forKey: key.rawValue)
    }

    static func set(_ value: Bool, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}
