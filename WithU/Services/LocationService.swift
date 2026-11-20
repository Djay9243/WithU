//
//  LocationService.swift
//  WithU
//
//  Wraps Core Location's async APIs. Location is only tracked while a trip is
//  active; the background session keeps updates flowing when the screen locks.
//

import CoreLocation
import Observation

@Observable
final class LocationService {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var currentLocation: CLLocation?
    private(set) var isStationary = false
    private(set) var isUpdating = false
    private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var updatesTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var serviceSession: CLServiceSession?

    init() {
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func refreshStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    /// Shows the system permission prompt (if needed) and waits for the answer.
    func requestAuthorization() async {
        let session = CLServiceSession(authorization: .whenInUse)
        serviceSession = session
        do {
            for try await diagnostic in session.diagnostics {
                if !diagnostic.authorizationRequestInProgress { break }
            }
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    /// Starts live updates for the duration of a trip.
    func startUpdates(for mode: TravelMode) {
        guard updatesTask == nil else { return }
        isUpdating = true
        backgroundSession = CLBackgroundActivitySession()
        let configuration = mode.liveUpdateConfiguration
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard let self, !Task.isCancelled else { break }
                    if let location = update.location {
                        self.currentLocation = location
                    }
                    self.isStationary = update.stationary
                    self.refreshStatus()
                }
            } catch {
                self?.lastError = error.localizedDescription
            }
            self?.isUpdating = false
        }
    }

    func stopUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        isUpdating = false
    }

    /// Grabs a single fix for planning a trip (ETA from the current position).
    func currentFix() async -> CLLocation? {
        if let currentLocation, currentLocation.timestamp.timeIntervalSinceNow > -120 {
            return currentLocation
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    currentLocation = location
                    return location
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }
}
