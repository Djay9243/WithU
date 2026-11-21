//
//  WithUIntents.swift
//  WithU
//
//  The Action button alert (press and hold it). Cancelling alerts is
//  deliberately not exposed here because it must go through Face ID or PIN.
//

import AppIntents
import Foundation

/// Assign to the Action button (Settings → Action Button → Shortcut → WithU).
/// The system's press-and-hold already guards against accidental presses, so
/// a single run alerts the whole circle.
struct ActionButtonAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Alert My Circle"
    static let description = IntentDescription("Put this on the Action button. Pressing and holding it alerts everyone in your circle with your location.")
    // Opens WithU when it can so location tracking can start while the alert runs.
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    // The trip lives in the app itself.
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Bring WithU forward when the surface allows it; the alert is sent
        // either way, since someone in danger can't be asked to confirm.
        if systemContext.currentMode.canContinueInForeground {
            try? await continueInForeground("Alerting your circle", alwaysConfirm: false)
        }
        let result = await MainActor.run { AppModel.shared.alertFromActionButton() }
        switch result {
        case .alerted(let circleName):
            return .result(dialog: "\(circleName) has been alerted with your location.")
        case .alreadyAlerting:
            return .result(dialog: "Your circle is already being alerted.")
        case .noContacts(let circleName):
            return .result(dialog: "Add someone to \(circleName) in WithU first, so there's someone to alert.")
        }
    }
}
