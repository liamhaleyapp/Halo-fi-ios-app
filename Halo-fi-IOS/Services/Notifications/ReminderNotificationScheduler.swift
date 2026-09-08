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
import UIKit
import UserNotifications

extension Notification.Name {
    /// userInfo["kind"] = reminder kind, ["month"] = YYYY-MM when present.
    static let ssiReminderOpened = Notification.Name("SSIReminderOpened")
    /// A digest was tapped: open Money → Needs your attention.
    static let attentionOpened = Notification.Name("AttentionOpened")
}

protocol NotificationScheduling: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func removeAllDeliveredNotifications()
}

extension UNUserNotificationCenter: NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

@MainActor
final class ReminderNotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotificationScheduler()

    private let center: NotificationScheduling
    private let lifetime: SessionLifetime
    private let signedIn: @MainActor () -> Bool
    private let pushRegistered: @MainActor () -> Bool
    private let historyKey = "notificationHistory.v2"
    private let defaults: UserDefaults
    /// A tap that arrived before the Money screen existed (the app was
    /// launched by the notification); the screen consumes it on appear.
    static var pendingAttentionOpen = false

    init(center: NotificationScheduling = UNUserNotificationCenter.current(),
         defaults: UserDefaults = .standard, lifetime: SessionLifetime = .shared,
         signedIn: (@MainActor () -> Bool)? = nil, pushRegistered: (@MainActor () -> Bool)? = nil) {
        self.center = center
        self.defaults = defaults
        self.lifetime = lifetime
        self.signedIn = signedIn ?? { PushRegistrar.shared.isSignedIn }
        self.pushRegistered = pushRegistered ?? { PushRegistrar.shared.isRegistered }
        super.init()
    }

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
        guard signedIn() else { return }
        let generation = lifetime.current
        // Old per-reminder requests from earlier builds.
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        guard lifetime.isCurrent(generation), signedIn() else { return }
        let legacy = pending.filter { $0.hasPrefix("ssi:") }
        if !legacy.isEmpty { center.removePendingNotificationRequests(withIdentifiers: legacy) }

        // Once the server can push, local digests would only duplicate it.
        if pushRegistered() {
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("halo:") })
            return
        }
        if cards.isEmpty {
            // Nothing open: a pending digest about resolved items must not fire.
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("halo:") })
            return
        }
        // A pending urgent note about a card that is no longer open is dropped.
        let openIds = Set(cards.map(\.id))
        let staleUrgent = pending.filter { $0.hasPrefix("halo:urgent:") && !openIds.contains(String($0.dropFirst("halo:urgent:".count).split(separator: ":").dropLast().joined(separator: ":"))) }
        if !staleUrgent.isEmpty { center.removePendingNotificationRequests(withIdentifiers: staleUrgent) }
        // nil = nothing NEW to say; whatever is pending stays scheduled.
        guard let next = NotificationPolicy.plan(cards: cards, now: now, history: history) else { return }
        let authorization = await center.authorizationStatus()
        guard lifetime.isCurrent(generation), signedIn() else { return }
        // Permission is asked on the Money tab, in the foreground, never from a
        // background refresh (an unexplained system prompt is disorienting).
        guard authorization == .authorized || authorization == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = next.title
        content.body = next.body
        content.sound = next.kind == .urgent ? .default : nil
        content.userInfo = ["kind": next.routeKind, "month": next.routeMonth]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next.fireAt)
        let id = next.kind == .urgent ? "halo:urgent:\(next.itemIds.first ?? "x"):\(generation)" : "halo:digest:\(generation)"
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        do {
            try await center.add(request)
            guard lifetime.isCurrent(generation), signedIn() else {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                center.removeDeliveredNotifications(withIdentifiers: [id])
                return
            }
            history = NotificationPolicy.recorded(next, into: history, now: now)
            Logger.info("Notifications: planned \(next.kind.rawValue) for \(next.fireAt)")
        } catch {
            Logger.warning("Notifications: could not schedule: \(error)")
        }
    }

    /// Clear both scheduled and already visible notifications synchronously.
    /// SessionLifetime invalidation in sign-out also rejects suspended plans.
    func clearForSignOut() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        defaults.removeObject(forKey: historyKey)
        Self.pendingAttentionOpen = false
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Someone using the app is never interrupted by a banner about it
    /// (Liam, 2026-09-05). A notification that arrives while HaloFi is in
    /// the foreground is swallowed; the screen already shows the same thing.
    ///
    /// Completion-handler form on purpose (TestFlight crash 2026-09-05,
    /// "Crashed. When opening push notification."): the `async` variants
    /// return on a cooperative background thread, and UIKit asserts when the
    /// notification-response completion runs off the main thread
    /// (`_updateSnapshotAndStateRestorationWithAction`). Everything here
    /// stays on main.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            let active = UIApplication.shared.applicationState == .active
            completionHandler(active ? [] : [.banner, .sound])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? ""
        let month = info["month"] as? String ?? ""
        DispatchQueue.main.async {
            guard PushRegistrar.shared.isSignedIn || UITestArchetype.isActive else {
                completionHandler()
                return
            }
            if kind == "attention" || kind == "bank_reconnect" || kind == "resources" {
                Self.pendingAttentionOpen = true
                NotificationCenter.default.post(name: .attentionOpened, object: nil)
            } else {
                NotificationCenter.default.post(name: .ssiReminderOpened, object: nil,
                                                userInfo: ["kind": kind, "month": month])
            }
            completionHandler()
        }
    }
}
