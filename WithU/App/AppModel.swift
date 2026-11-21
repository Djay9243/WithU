//
//  AppModel.swift
//  WithU
//
//  Root object: settings, the trusted circles, permissions and trip planning.
//

import CoreLocation
import Foundation
import Observation
import SwiftUI

enum AppTab: Hashable {
    case map, journal, circle, search
}

@Observable
final class AppModel {
    static let shared = AppModel()

    /// The selected tab, so screens can jump to Circle or Settings.
    var selectedTab: AppTab = .map

    /// A place picked in the Search tab, for the map to open its trip sheet.
    var placeToShowOnMap: Destination?

    /// The search sheet, opened from the search icon in the tab bar.
    var showingSearch = false

    /// Search hands a place to the map and switches to it.
    func showOnMap(_ destination: Destination) {
        placeToShowOnMap = destination
        selectedTab = .map
        showingSearch = false
    }

    /// Opening the app from a notification or the Live Activity lands on the
    /// trip, which is always on screen while it runs.
    func showTrip() {
        selectedTab = .map
    }

    /// Handles `withu://trip` from the Live Activity and Lock Screen.
    func handle(url: URL) {
        guard url.scheme == "withu" else { return }
        showTrip()
    }

    var hasCompletedOnboarding: Bool {
        didSet { Persistence.set(hasCompletedOnboarding, for: .onboardingComplete) }
    }

    var settings: AppSettings {
        didSet { Persistence.save(settings, for: .settings) }
    }

    /// Every circle the person has created. There is always at least one.
    private(set) var circles: [TrustedCircle] {
        didSet { Persistence.save(circles, for: .circles) }
    }

    /// The last three places picked in search, newest first.
    private(set) var recentDestinations: [Destination] {
        didSet { Persistence.save(recentDestinations, for: .recentDestinations) }
    }

    func rememberDestination(_ destination: Destination) {
        var recents = recentDestinations.filter { $0.id != destination.id }
        recents.insert(destination, at: 0)
        recentDestinations = Array(recents.prefix(3))
    }

    /// Places tagged Home, Work or Gym, in that order.
    private(set) var savedPlaces: [SavedPlace] {
        didSet { Persistence.save(savedPlaces, for: .savedPlaces) }
    }

    func tag(for destination: Destination) -> PlaceTag? {
        savedPlaces.first { $0.destination.id == destination.id }?.tag
    }

    /// Gives the place this tag, moving the tag off whichever place had it.
    func setTag(_ tag: PlaceTag?, for destination: Destination) {
        var places = savedPlaces.filter { $0.destination.id != destination.id }
        if let tag {
            places.removeAll { $0.tag == tag }
            places.append(SavedPlace(tag: tag, destination: destination))
        }
        savedPlaces = places.sorted {
            PlaceTag.allCases.firstIndex(of: $0.tag) ?? 0 < PlaceTag.allCases.firstIndex(of: $1.tag) ?? 0
        }
    }

    let location = LocationService()
    let notifications = NotificationService()
    let auth = AuthenticationService()
    let routing = RoutingService()
    /// Stories and finished journeys.
    let stories = StoryStore()
    let trip: TripManager
    /// iCloud delivery to your circle; nil until `WithUCloudSyncEnabled` is on.
    let cloud: CloudCircleService?

    private init() {
        hasCompletedOnboarding = Persistence.bool(for: .onboardingComplete)
        settings = Persistence.load(AppSettings.self, for: .settings) ?? AppSettings()
        recentDestinations = Persistence.load([Destination].self, for: .recentDestinations) ?? []
        savedPlaces = Persistence.load([SavedPlace].self, for: .savedPlaces) ?? []
        if let saved = Persistence.load([TrustedCircle].self, for: .circles), !saved.isEmpty {
            circles = saved
        } else {
            // Migrate the single contact list from earlier builds into one circle.
            let legacy = Persistence.load([TrustedContact].self, for: .contacts) ?? []
            circles = [TrustedCircle(name: TrustedCircle.defaultName, contacts: legacy)]
        }
        trip = TripManager(location: location, notifications: notifications, auth: auth)
        cloud = CloudCircleService.isEnabled ? CloudCircleService() : nil
        trip.onArrived = { [unowned self] journey in
            stories.record(journey)
        }
        if settings.selectedCircleID == nil || !circles.contains(where: { $0.id == settings.selectedCircleID }) {
            settings.selectedCircleID = circles[0].id
        }

        // Tapping a notification opens the trip, or Circles for someone else's.
        notifications.onOpen = { [unowned self] fromCircle in
            if fromCircle, !trip.isActive {
                selectedTab = .circle
            } else {
                showTrip()
            }
        }
        notifications.onRemoteNotification = { [unowned self] in
            Task { await cloud?.refresh() }
        }

        if let cloud {
            cloud.contactLookup = { [unowned self] id in allContacts().first { $0.id == id } }
            cloud.contactForRemoteUser = { [unowned self] user in
                allContacts().first { $0.link?.remoteUserID == user }
            }
            cloud.applyInviteReply = { [unowned self] inviteID, user, accepted in
                applyInviteReply(inviteID: inviteID, remoteUserID: user, accepted: accepted)
            }
            cloud.myName = { [unowned self] in settings.userName.isEmpty ? "Someone" : settings.userName }
            cloud.myPhone = { [unowned self] in settings.userPhone }
            cloud.currentDestination = { [unowned self] in trip.isSOSOnly ? nil : trip.plan?.destination.name }
            trip.useSync(cloud)
            Task { await cloud.start() }
        }

        // Resume a trip that was running when the app was closed.
        trip.restore(settings: settings)
    }

    // MARK: - Greeting

    var greetingName: String {
        let trimmed = settings.userName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "there" }
        return String(trimmed.split(separator: " ").first ?? Substring(trimmed))
    }

    var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Circles

    /// The circle trips are shared with.
    var selectedCircle: TrustedCircle {
        circles.first(where: { $0.id == settings.selectedCircleID }) ?? circles[0]
    }

    // MARK: - Action button

    enum ActionButtonAlertResult {
        case alerted(circleName: String)
        case alreadyAlerting
        case noContacts(circleName: String)
    }

    /// Alerts the whole circle straight away: during a trip it's the same as
    /// the Emergency button; without one it starts an SOS that shares your
    /// location. No Face ID: in an emergency there may be no time for it.
    func alertFromActionButton() -> ActionButtonAlertResult {
        if trip.phase == .alerting || trip.phase == .enteringPIN {
            return .alreadyAlerting
        }
        if trip.isActive {
            trip.emergency()
            return .alerted(circleName: trip.circleName)
        }
        let circle = selectedCircle
        guard !circle.contacts.isEmpty else { return .noContacts(circleName: circle.name) }
        trip.startSOS(circle: circle, settings: settings)
        return .alerted(circleName: circle.name)
    }

    /// Contacts in the selected circle.
    var contacts: [TrustedContact] { selectedCircle.contacts }

    func circle(withID id: UUID) -> TrustedCircle? {
        circles.first { $0.id == id }
    }

    func selectCircle(_ circle: TrustedCircle) {
        settings.selectedCircleID = circle.id
    }

    @discardableResult
    func addCircle(named name: String) -> TrustedCircle? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let circle = TrustedCircle(name: trimmed)
        circles.append(circle)
        return circle
    }

    /// Creates a circle with its people in one go and makes it the selected one.
    func createCircle(named name: String, with people: [ContactCandidate]) {
        guard let circle = addCircle(named: name) else { return }
        addContacts(people, to: circle.id)
        settings.selectedCircleID = circle.id
    }

    func renameCircle(_ circle: TrustedCircle, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = circles.firstIndex(where: { $0.id == circle.id }) else { return }
        circles[index].name = trimmed
    }

    /// Removes a circle. The last remaining circle can't be deleted.
    func deleteCircle(_ circle: TrustedCircle) {
        guard circles.count > 1 else { return }
        circles.removeAll { $0.id == circle.id }
        stories.removeFromAudiences(circleID: circle.id, memberIDs: Set(circle.contacts.map(\.id)))
        if settings.selectedCircleID == circle.id {
            settings.selectedCircleID = circles[0].id
        }
    }

    // MARK: - Contacts within a circle

    func addContact(_ candidate: ContactCandidate, to circleID: UUID) {
        guard let index = circles.firstIndex(where: { $0.id == circleID }),
              !isInCircle(candidate, circleID: circleID) else { return }
        let contact = TrustedContact(name: candidate.name,
                                     phoneNumber: candidate.phoneNumber,
                                     colorIndex: circles[index].contacts.count)
        circles[index].contacts.append(contact)
        invite(contact.id, in: circleID)
    }

    /// Sends (or resends) an invite so the person can confirm they have WithU.
    func invite(_ contactID: UUID, in circleID: UUID) {
        guard let cloud, cloud.isAvailable,
              let circle = circle(withID: circleID),
              let contact = circle.contacts.first(where: { $0.id == contactID }) else { return }
        Task {
            guard let inviteID = await cloud.sendInvite(to: contact, circleName: circle.name) else { return }
            updateContact(contactID) { $0.link = ContactLink(status: .invited, inviteID: inviteID) }
        }
    }

    private func updateContact(_ id: UUID, _ change: (inout TrustedContact) -> Void) {
        for circleIndex in circles.indices {
            if let index = circles[circleIndex].contacts.firstIndex(where: { $0.id == id }) {
                change(&circles[circleIndex].contacts[index])
            }
        }
    }

    private func allContacts() -> [TrustedContact] {
        circles.flatMap(\.contacts)
    }

    /// An invite was accepted or declined on the other person's phone.
    private func applyInviteReply(inviteID: String, remoteUserID: String, accepted: Bool) {
        guard let contact = allContacts().first(where: { $0.link?.inviteID == inviteID }) else { return }
        updateContact(contact.id) {
            $0.link = ContactLink(status: accepted ? .connected : .declined,
                                  inviteID: inviteID,
                                  remoteUserID: accepted ? remoteUserID : nil)
        }
    }

    /// Saves your phone number from your contact card so people can invite you.
    func setOwnPhone(_ phone: String?) {
        guard let phone, !phone.isEmpty else { return }
        settings.userPhone = phone
        Task { await cloud?.phoneNumberChanged() }
    }

    /// Adds everyone picked in the contact picker, skipping people already there.
    func addContacts(_ candidates: [ContactCandidate], to circleID: UUID) {
        for candidate in candidates {
            addContact(candidate, to: circleID)
        }
    }

    func removeContacts(at offsets: IndexSet, from circleID: UUID) {
        guard let index = circles.firstIndex(where: { $0.id == circleID }) else { return }
        let removed = offsets.map { circles[index].contacts[$0].id }
        circles[index].contacts.remove(atOffsets: offsets)
        // Someone who leaves a circle no longer sees its stories.
        stories.removeFromAudiences(memberIDs: Set(removed))
    }

    /// Turns stories on or off for a circle, e.g. for a "safety only" circle.
    func setReceivesStories(_ enabled: Bool, for circleID: UUID) {
        guard let index = circles.firstIndex(where: { $0.id == circleID }) else { return }
        circles[index].receivesStories = enabled
        if !enabled {
            stories.removeFromAudiences(circleID: circleID, memberIDs: Set(circles[index].contacts.map(\.id)))
        }
    }

    /// Circles that can be picked as a story audience.
    var storyCircles: [TrustedCircle] {
        circles.filter { $0.receivesStories && !$0.contacts.isEmpty }
    }

    /// The audience a new story starts with: the circle the current trip is
    /// shared with, if it accepts stories.
    var defaultStoryAudience: StoryAudience {
        let circle = trip.circleID.flatMap { self.circle(withID: $0) } ?? selectedCircle
        guard circle.receivesStories, !circle.contacts.isEmpty else { return .onlyMe }
        return StoryAudience(circleIDs: [circle.id])
    }

    /// A readable summary of who can see a story, e.g. "Family, Mum".
    func audienceSummary(_ audience: StoryAudience) -> String {
        if audience.isPrivate { return "Only Me" }
        let circleNames = audience.circleIDs.compactMap { circle(withID: $0)?.name }
        let people = allContacts().filter { audience.memberIDs.contains($0.id) }.map(\.name)
        let names = circleNames + people
        return names.isEmpty ? "Only Me" : names.formatted(.list(type: .and))
    }

    /// Reorders the alert chain.
    func moveContacts(from source: IndexSet, to destination: Int, in circleID: UUID) {
        guard let index = circles.firstIndex(where: { $0.id == circleID }) else { return }
        circles[index].contacts.move(fromOffsets: source, toOffset: destination)
    }

    func isInCircle(_ candidate: ContactCandidate, circleID: UUID) -> Bool {
        circle(withID: circleID)?.contacts.contains {
            $0.name == candidate.name && $0.phoneNumber == candidate.phoneNumber
        } ?? false
    }

    // MARK: - Permissions

    func refreshPermissions() async {
        location.refreshStatus()
        await notifications.refreshStatus()
    }

    // MARK: - Trips

    enum PlanningError: LocalizedError {
        case noLocation
        case noContacts(String)
        var errorDescription: String? {
            switch self {
            case .noLocation: "Can't find your location. Check Location in Settings."
            case .noContacts(let circle): "Add at least one trusted contact to “\(circle)” before starting a trip."
            }
        }
    }

    /// Asks Apple Maps for the route and estimated arrival from where the person is now.
    func planRoute(to destination: Destination, mode: TravelMode) async throws -> RouteResult {
        guard let fix = await location.currentFix() else { throw PlanningError.noLocation }
        return try await routing.route(from: fix.coordinate, to: destination, mode: mode, preferBusy: settings.preferBusyRoute)
    }

    func makePlan(destination: Destination, mode: TravelMode, route: RouteResult, deadlineEnabled: Bool) -> TripPlan {
        TripPlan(destination: destination,
                 mode: mode,
                 expectedTravelTime: route.expectedTravelTime,
                 distance: route.distance,
                 checkOnStop: settings.checkOnStop,
                 stopThresholdMinutes: settings.stopThresholdMinutes,
                 deadline: deadlineEnabled ? settings.nextHomeDeadline() : nil)
    }

    /// Starts the trip and shares it with the given circle (the selected one by default).
    func startTrip(plan: TripPlan, route: RouteResult, circle: TrustedCircle? = nil) throws {
        let circle = circle ?? selectedCircle
        guard !circle.contacts.isEmpty else { throw PlanningError.noContacts(circle.name) }
        settings.lastTravelMode = plan.mode
        settings.selectedCircleID = circle.id
        trip.start(plan: plan, route: route, circle: circle, settings: settings)
    }
}
