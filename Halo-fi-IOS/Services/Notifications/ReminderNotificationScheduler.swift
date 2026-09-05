//
//  ReminderNotificationScheduler.swift
//  Halo-fi-IOS
//
//  LOCAL notifications, planned by NotificationPolicy (Liam, 2026-09-05):
//  at most one calm digest a day at 9 a.m., plus at most one specific
//  "HaloFi needs you" for something pressing, each item announced once.
//  There is no push infrastructure yet, so the plan is recomputed every
//  time the app refreshes its attention cards and the pending request is
//  replaced. Tapping a notification lands on the right screen.
//

import Foundation
import UserNotifications

extension Notification.Name {
    /// userInfo["kind"] = reminder kind, ["month"] = YYYY-MM when present.
    static let ssiReminderOpened = Notification.Name("SSIReminderOpened")
    /// A digest was tapped: open Money → Needs your attention.
    static let attentionOpened = Notification.Name("AttentionOpened")
}

final class ReminderNotificationScheduler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ReminderNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let historyKey = "notificationHistory.v2"
    private let defaults = UserDefaults.standard
    private static let requestIds = ["halo:digest", "halo:urgent"]

    /// Call once at launch so taps on a notification reach the app.
    func install() {
        center.delegate = self
    }

    private var history: NotificationHistory {
        get {
            guard let data = defaults.data(forKey: historyKey),
                  let h = try? JSONDecoder().decode(NotificationHistory.self, from: data) else { return NotificationHistory() }
            return h
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: historyKey) }
    }

    /// Re-plan from the current cards. Replaces whatever was pending, so a
    /// resolved card never fires and a new urgent one is not missed.
    func plan(cards: [AttentionCard], now: Date = Date()) async {
        if UITestArchetype.isActive { return }
        // Old per-reminder requests from earlier builds.
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let legacy = pending.filter { $0.hasPrefix("ssi:") }
        if !legacy.isEmpty { center.removePendingNotificationRequests(withIdentifiers: legacy) }

        guard let next = NotificationPolicy.plan(cards: cards, now: now, history: history) else {
            center.removePendingNotificationRequests(withIdentifiers: Self.requestIds)
            return
        }
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = next.title
        content.body = next.body
        content.sound = next.kind == .urgent ? .default : nil
        content.userInfo = ["kind": next.routeKind, "month": next.routeMonth]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next.fireAt)
        let id = next.kind == .urgent ? "halo:urgent" : "halo:digest"
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        do {
            try await center.add(request)
            history = NotificationPolicy.recorded(next, into: history)
            Logger.info("Notifications: planned \(next.kind.rawValue) for \(next.fireAt)")
        } catch {
            Logger.warning("Notifications: could not schedule: \(error)")
        }
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
            if kind == "attention" || kind == "bank_reconnect" || kind == "resources" {
                NotificationCenter.default.post(name: .attentionOpened, object: nil)
            } else {
                NotificationCenter.default.post(name: .ssiReminderOpened, object: nil,
                                                userInfo: ["kind": kind, "month": month])
            }
        }
    }
}
