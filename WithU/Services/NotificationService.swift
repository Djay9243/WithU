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
    case remindLater
    case needHelp
    case opened
}

@Observable
final class NotificationService: NSObject {
    static let checkInCategory = "WITHU_CHECK_IN"
    /// A long stop: Remind Me Later instead of Add 10 Min.
    static let stopCheckInCategory = "WITHU_STOP_CHECK_IN"
    /// The second long-stop check-in, after Remind Me Later: no more snoozing.
    static let stopFollowUpCategory = "WITHU_STOP_FOLLOW_UP"
    static let okAction = "WITHU_OK"
    static let helpAction = "WITHU_HELP"
    static let addTimeAction = "WITHU_ADD_TIME"
    static let remindLaterAction = "WITHU_REMIND_LATER"
    static let checkInIdentifier = "withu.checkin"
    static let checkInReminderIdentifier = "withu.checkin.reminder"
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
        let ok = UNNotificationAction(identifier: Self.okAction, title: "I'm Fine", options: [.authenticationRequired])
        let addTime = UNNotificationAction(identifier: Self.addTimeAction, title: "Add 10 Min", options: [.authenticationRequired])
        let remindLater = UNNotificationAction(identifier: Self.remindLaterAction, title: "Remind Me Later", options: [.authenticationRequired])
        let help = UNNotificationAction(identifier: Self.helpAction, title: "I Need Help", options: [.destructive, .foreground])
        let category = UNNotificationCategory(identifier: Self.checkInCategory, actions: [ok, addTime, help], intentIdentifiers: [])
        let stop = UNNotificationCategory(identifier: Self.stopCheckInCategory, actions: [ok, remindLater, help], intentIdentifiers: [])
        let stopFollowUp = UNNotificationCategory(identifier: Self.stopFollowUpCategory, actions: [ok, help], intentIdentifiers: [])
        center.setNotificationCategories([category, stop, stopFollowUp])
    }

    private static let checkInCategories: Set<String> = [checkInCategory, stopCheckInCategory, stopFollowUpCategory]

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

    /// Posts the check-in so it reaches the person even in a Focus, plus one
    /// gentle reminder shortly before the circle would be told.
    /// `isFollowUp` marks the second long-stop check-in, which can't be put off again.
    /// A `delay` hands the check-in to the system to deliver later, so it still
    /// arrives if WithU is closed in the meantime.
    func postCheckIn(reason: CheckInReason, window: TimeInterval, isFollowUp: Bool = false, after delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        let category: String
        if reason == .unusualStop && isFollowUp {
            content.title = "Checking in again"
            content.body = "You're still stopped. Tap I'm Fine, or we'll alert your circle in \(Format.responseTime(Int(window)))."
            category = Self.stopFollowUpCategory
        } else if reason == .unusualStop {
            content.title = "You've been stopped for a while"
            content.body = "Share a moment with your circle. If you don't share or move on in \(Format.responseTime(Int(window))), we'll alert them."
            category = Self.stopCheckInCategory
        } else {
            content.title = "Everything okay?"
            content.subtitle = reason.title
            content.body = "Tap I'm Fine when you have a moment. You have \(Format.responseTime(Int(window)))."
            category = Self.checkInCategory
        }
        content.categoryIdentifier = category
        content.sound = .default
        // Time Sensitive delivery needs the entitlement, which requires a paid
        // developer team. Without it the system quietly delivers this as a normal alert.
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        let trigger = delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        center.add(UNNotificationRequest(identifier: Self.checkInIdentifier, content: content, trigger: trigger))

        // A second, gentle nudge before the circle is told.
        let lead = TripRules.checkInReminderLead
        guard window > lead else { return }
        let reminder = UNMutableNotificationContent()
        reminder.title = "Still with us?"
        reminder.body = "Tap I'm Fine, or we'll let your circle know in \(Format.responseTime(Int(lead))) so they can check on you."
        reminder.categoryIdentifier = category
        reminder.sound = criticalAlertsAllowed ? .defaultCritical : .default
        reminder.interruptionLevel = criticalAlertsAllowed ? .critical : .timeSensitive
        reminder.relevanceScore = 1
        let reminderTrigger = UNTimeIntervalNotificationTrigger(timeInterval: delay + window - lead, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.checkInReminderIdentifier, content: reminder, trigger: reminderTrigger))
    }

    /// Drops a check-in that was scheduled for later but hasn't arrived yet.
    func cancelScheduledCheckIn() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.checkInIdentifier, Self.checkInReminderIdentifier])
    }

    func postAlertStarted(circleName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your circle is checking on you"
        let name = circleName.isEmpty ? "Your circle" : circleName
        content.body = "\(name) can see where you last were and your battery. Open WithU when you're okay."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: Self.alertIdentifier, content: content, trigger: nil)
        center.add(request)
    }

    func postArrived(destination: String) {
        let content = UNMutableNotificationContent()
        content.title = "You made it 🎉"
        content.body = "Your circle knows you reached \(destination). Location sharing is off."
        content.sound = .default
        content.interruptionLevel = .active
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func clearCheckIn() {
        let ids = [Self.checkInIdentifier, Self.checkInReminderIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
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
            guard Self.checkInCategories.contains(category) else { return }
            switch action {
            case Self.okAction: onCheckInResponse?(.ok)
            case Self.addTimeAction: onCheckInResponse?(.addTime)
            case Self.remindLaterAction: onCheckInResponse?(.remindLater)
            case Self.helpAction: onCheckInResponse?(.needHelp)
            default: onCheckInResponse?(.opened)
            }
        }
    }
}
