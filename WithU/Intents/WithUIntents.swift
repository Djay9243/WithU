//
//  WithUIntents.swift
//  WithU
//
//  Siri and Shortcuts: "Start a trip with WithU". Cancelling alerts is
//  deliberately not exposed here because it must go through Face ID or PIN.
//

import AppIntents
import Foundation

nonisolated enum TravelModeOption: String, AppEnum {
    case walk, drive, cycle, transit

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Travel mode")

    static let caseDisplayRepresentations: [TravelModeOption: DisplayRepresentation] = [
        .walk: "Walking",
        .drive: "Driving",
        .cycle: "Cycling",
        .transit: "Transit"
    ]

    var travelMode: TravelMode {
        switch self {
        case .walk: .walk
        case .drive: .drive
        case .cycle: .cycle
        case .transit: .transit
        }
    }
}

/// Lets Siri and Shortcuts refer to a circle by name.
nonisolated struct CircleEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Circle")
    static let defaultQuery = CircleQuery()

    var id: UUID
    var name: String
    var memberCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(memberCount) contacts")
    }

    init(_ circle: TrustedCircle) {
        id = circle.id
        name = circle.name
        memberCount = circle.contacts.count
    }
}

nonisolated struct CircleQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CircleEntity] {
        await MainActor.run {
            AppModel.shared.circles.filter { identifiers.contains($0.id) }.map(CircleEntity.init)
        }
    }

    func suggestedEntities() async throws -> [CircleEntity] {
        await MainActor.run { AppModel.shared.circles.map(CircleEntity.init) }
    }

    func defaultResult() async -> CircleEntity? {
        await MainActor.run { CircleEntity(AppModel.shared.selectedCircle) }
    }
}

struct StartTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Trip"
    static let description = IntentDescription("Starts a WithU trip to a destination and shares your progress with your circle.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Destination", requestValueDialog: "Where are you heading?")
    var destination: String

    @Parameter(title: "Travel mode", default: .walk)
    var mode: TravelModeOption

    @Parameter(title: "Share with circle")
    var circle: CircleEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a trip to \(\.$destination)") {
            \.$mode
            \.$circle
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let plan = try await MainActor.run { () -> Task<TripPlan, Error> in
            let model = AppModel.shared
            let query = destination
            let travelMode = mode.travelMode
            let circleID = circle?.id
            return Task { @MainActor in
                try await model.startTrip(toQuery: query, mode: travelMode, circleID: circleID)
            }
        }.value
        let minutes = Int((plan.expectedTravelTime / 60).rounded())
        let circleName = await MainActor.run { AppModel.shared.trip.circleName }
        return .result(dialog: "Trip to \(plan.destination.name) started. About \(minutes) minutes. \(circleName) is with you.")
    }
}

struct TripStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Trip Status"
    static let description = IntentDescription("Tells you how long is left on your current WithU trip.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            let trip = AppModel.shared.trip
            guard trip.isActive, let plan = trip.plan else { return "You don't have an active trip." }
            let remaining = max(trip.endsAt.timeIntervalSinceNow, 0)
            let minutes = Int((remaining / 60).rounded())
            return "You're heading to \(plan.destination.name) with about \(minutes) minutes left."
        }
        return .result(dialog: "\(message)")
    }
}

nonisolated struct WithUShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripIntent(),
            phrases: [
                "Start a trip with \(.applicationName)",
                "Walk me home with \(.applicationName)",
                "Start a \(\.$mode) trip with \(.applicationName)",
                "Share my trip with \(\.$circle) in \(.applicationName)"
            ],
            shortTitle: "Start Trip",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: TripStatusIntent(),
            phrases: [
                "How long is left on my \(.applicationName) trip",
                "Check my \(.applicationName) trip"
            ],
            shortTitle: "Trip Status",
            systemImageName: "timer"
        )
    }
}
