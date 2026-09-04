//
//  ReminderNotificationScheduler.swift
//  Halo-fi-IOS
//
//  WP6 — turns backend reminders into LOCAL notifications. There is no
//  push infrastructure; the app schedules one notification per reminder
//  id the first time it sees it (UserDefaults remembers what was already
//  notified, so a reminder is "one respectful notification", never a
//  drip). Tapping a notification lands on the Benefits tab.
//

import Foundation
import UserNotifications

extension Notification.Name {
    /// userInfo["kind"] = reminder kind, ["month"] = YYYY-MM when present.
    static let ssiReminderOpened = Notification.Name("SSIReminderOpened")
}

final class ReminderNotificationScheduler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ReminderNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let notifiedKey = "ssiRemindersNotified.v1"
    private let defaults = UserDefaults.standard

    /// Call once at launch so taps on a notification reach the app.
    func install() {
        center.delegate = self
    }

    /// Schedule notifications for reminders not yet notified; drop pending
    /// ones whose reminder no longer exists (receipt attached, month marked).
    func sync(_ reminders: [SSIReminder]) async {
        if UITestArchetype.isActive { return }
        let wanted = reminders.filter { $0.kind != "month_end_review" || true }
        let ids = Set(wanted.map(\.id))

        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let stale = pending.filter { $0.hasPrefix("ssi:") && !ids.contains(String($0.dropFirst(4))) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        var notified = Set(defaults.stringArray(forKey: notifiedKey) ?? [])
        let fresh = wanted.filter { !notified.contains($0.id) }
        guard !fresh.isEmpty else { return }

        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return }

        for reminder in fresh {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["kind": reminder.kind, "month": reminder.month ?? ""]
            let request = UNNotificationRequest(
                identifier: "ssi:\(reminder.id)",
                content: content,
                trigger: Self.trigger(for: reminder)
            )
            do {
                try await center.add(request)
                notified.insert(reminder.id)
            } catch {
                Logger.warning("ReminderNotificationScheduler: could not schedule \(reminder.id): \(error)")
            }
        }
        // Keep the list bounded.
        defaults.set(Array(notified.suffix(200)), forKey: notifiedKey)
    }

    /// submit_package → 9 a.m. on its due date (or in a minute if that has
    /// passed). Everything else → the next 9 a.m., so nothing buzzes at night.
    private static func trigger(for reminder: SSIReminder) -> UNNotificationTrigger {
        let cal = Calendar.current
        var fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        if reminder.kind == "submit_package", let due = reminder.dueOn {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: due), let at9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) {
                fire = at9
            }
        }
        if fire <= Date() {
            if reminder.kind == "submit_package" {
                return UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            }
            fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
        }
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? ""
        let month = info["month"] as? String ?? ""
        await MainActor.run {
            NotificationCenter.default.post(name: .ssiReminderOpened, object: nil,
                                            userInfo: ["kind": kind, "month": month])
        }
    }
}
