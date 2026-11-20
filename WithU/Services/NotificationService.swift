//
//  NotificationService.swift
//  WithU
//
//  Time Sensitive (and, once Apple approves the entitlement, Critical) local
//  notifications for check-ins and alerts, with actions the person can answer
//  straight from the Lock Screen.
//

import Foundation
import Observation
import UserNotifications
import UIKit

nonisolated enum CheckInResponse: Sendable {
    case ok
    case addTime
    case needHelp
    case opened
}

@Observable
final class NotificationService: NSObject {
    static let checkInCategory = "WITHU_CHECK_IN"
    static let okAction = "WITHU_OK"
    static let helpAction = "WITHU_HELP"
    static let addTimeAction = "WITHU_ADD_TIME"
    static let checkInIdentifier = "withu.checkin"
    static let alertIdentifier = "withu.alert"

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var criticalAlertsAllowed = false
    private(set) var timeSensitiveAllowed = false

    /// Called when the person answers a check-in from a notification.
    var onCheckInResponse: ((CheckInResponse) -> Void)?
    /// Called whenever a WithU notification is tapped or answered, so the app
    /// can bring the trip on screen.
    /// The flag is true for notifications about someone else's trip or invite.
    var onOpen: ((Bool) -> Void)?
    /// A CloudKit push arrived: invites, replies, trips or responses changed.
    var onRemoteNotification: (() -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
        Task { await refreshStatus() }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    private func registerCategories() {
        let ok = UNNotificationAction(identifier: Self.okAction, title: "I'm OK", options: [.authenticationRequired])
        let addTime = UNNotificationAction(identifier: Self.addTimeAction, title: "Add 10 Min", options: [.authenticationRequired])
        let help = UNNotificationAction(identifier: Self.helpAction, title: "I Need Help", options: [.destructive, .foreground])
        let category = UNNotificationCategory(identifier: Self.checkInCategory, actions: [ok, addTime, help], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async {
        // `.criticalAlert` is ignored by the system until the entitlement is granted.
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .criticalAlert]
        _ = try? await center.requestAuthorization(options: options)
        await refreshStatus()
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        criticalAlertsAllowed = settings.criticalAlertSetting == .enabled
        timeSensitiveAllowed = settings.timeSensitiveSetting == .enabled
    }

    /// Posts the "Are you OK?" prompt so it reaches the person even in a Focus.
    func postCheckIn(reason: CheckInReason, window: TimeInterval) {
        let content = UNMutableNotificationContent()
        if reason == .unusualStop {
            content.title = "Found something nice? 📸"
            content.subtitle = reason.title
            content.body = "Share a moment, or tap I'm OK within \(Format.responseTime(Int(window))) so your circle isn't alerted."
        } else {
            content.title = "Are You OK?"
            content.subtitle = reason.title
            content.body = "Reply within \(Format.responseTime(Int(window))) or your circle will be alerted."
        }
        content.categoryIdentifier = Self.checkInCategory
        content.sound = criticalAlertsAllowed ? .defaultCritical : .default
        // Time Sensitive delivery needs the entitlement, which requires a paid
        // developer team. Without it the system quietly delivers this as a normal alert.
        content.interruptionLevel = criticalAlertsAllowed ? .critical : .timeSensitive
        content.relevanceScore = 1
        let request = UNNotificationRequest(identifier: Self.checkInIdentifier, content: content, trigger: nil)
        center.add(request)
    }

    func postAlertStarted(contactName: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Alerting Your Circle"
        if let contactName {
            content.body = "\(contactName) is being told first. Open WithU to cancel."
        } else {
            content.body = "Your circle is being told. Open WithU to cancel."
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: Self.alertIdentifier, content: content, trigger: nil)
        center.add(request)
    }

    func postArrived(destination: String) {
        let content = UNMutableNotificationContent()
        content.title = "You've Arrived"
        content.body = "Your circle was told you reached \(destination) safely. Sharing has stopped."
        content.sound = .default
        content.interruptionLevel = .active
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func clearCheckIn() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.checkInIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.checkInIdentifier])
    }

    func clearAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Pushes from your circle (CloudKit adds a "ck" key) always show, and
        // the app refreshes. Your own check-ins are already full screen in the app.
        let isCircle = notification.request.content.userInfo["ck"] != nil
        if isCircle {
            await MainActor.run { onRemoteNotification?() }
            return [.banner, .sound, .list]
        }
        let isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
        return isActive ? [] : [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let isCircle = response.notification.request.content.userInfo["ck"] != nil
        await MainActor.run {
            if isCircle { onRemoteNotification?() }
            if action != UNNotificationDismissActionIdentifier {
                onOpen?(isCircle)
            }
            guard category == Self.checkInCategory else { return }
            switch action {
            case Self.okAction: onCheckInResponse?(.ok)
            case Self.addTimeAction: onCheckInResponse?(.addTime)
            case Self.helpAction: onCheckInResponse?(.needHelp)
            default: onCheckInResponse?(.opened)
            }
        }
    }
}
