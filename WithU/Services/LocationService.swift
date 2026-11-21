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
        // Only held while the prompt is up. Keeping a session alive for the
        // life of the app (with the location background mode) kept the blue
        // location arrow in the Dynamic Island after trips had ended.
        let session = CLServiceSession(authorization: .whenInUse)
        do {
            for try await diagnostic in session.diagnostics {
                if !diagnostic.authorizationRequestInProgress { break }
            }
        } catch {
            lastError = error.localizedDescription
        }
        session.invalidate()
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
                    try Task.checkCancellation()
                    guard let self else { break }
                    if let location = update.location {
                        self.currentLocation = location
                    }
                    self.isStationary = update.stationary
                    self.refreshStatus()
                }
            } catch is CancellationError {
                // Stopped by `stopUpdates()`.
            } catch {
                self?.lastError = error.localizedDescription
            }
            // A cancelled task must not touch the state of a newer trip.
            if !Task.isCancelled { self?.isUpdating = false }
        }
    }

    func stopUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        isUpdating = false
    }

    /// Ends a background location session left over from an earlier run of
    /// the app (e.g. it was closed or replaced mid-trip). The system keeps such
    /// a session, and its arrow in the Dynamic Island, alive across launches;
    /// creating one and invalidating it straight away ends it for good.
    func endLeftoverBackgroundActivity() {
        guard updatesTask == nil else { return }
        CLBackgroundActivitySession().invalidate()
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }

    /// Grabs a single fix for planning a trip (ETA from the current position).
    /// Gives up after a few seconds so location is never left running.
    func currentFix() async -> CLLocation? {
        if let currentLocation, currentLocation.timestamp.timeIntervalSinceNow > -120 {
            return currentLocation
        }
        let fix = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        try Task.checkCancellation()
                        if let location = update.location { return location }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let fix { currentLocation = fix }
        return fix
    }
}
