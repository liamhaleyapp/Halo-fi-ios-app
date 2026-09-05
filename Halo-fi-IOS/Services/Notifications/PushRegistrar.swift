//
//  PushRegistrar.swift
//  Halo-fi-IOS
//
//  Real push (2026-09-05): once notifications are allowed, the app asks iOS
//  for an APNs token and hands it to the backend with the device's time
//  zone, so the server can notify at the user's 9 a.m. even when the app
//  has not been opened for days. The token is refreshed on every launch
//  and forgotten on sign-out.
//

import Foundation
import UIKit
import UserNotifications

final class PushRegistrar: NSObject, @unchecked Sendable {
    static let shared = PushRegistrar()

    private let tokenKey = "pushDeviceToken.v1"
    private let registeredKey = "pushDeviceRegistered.v1"
    private var pendingToken: String?
    /// True once /me/devices accepted this device: the server pushes, the
    /// app stops scheduling local digests.
    var isRegistered: Bool { UserDefaults.standard.bool(forKey: registeredKey) }

    /// Ask for permission in the foreground (first Money screen), then
    /// register. Never called from a background refresh.
    func requestPermissionIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { registerIfAllowed(); return }
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if ok { registerIfAllowed() }
    }
    /// Set by UserManager; a token is only sent for a signed-in user.
    var isSignedIn = false {
        didSet { if isSignedIn { Task { await sendIfSignedIn() } } }
    }

    /// Ask iOS for a token if the user already allowed notifications.
    func registerIfAllowed() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// From the app delegate: the token as hex.
    func didReceive(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        pendingToken = token
        Task { await sendIfSignedIn() }
    }

    /// Call after sign-in too: a token that arrived before the session was
    /// restored is sent once the user is known.
    func sendIfSignedIn() async {
        guard let token = pendingToken ?? UserDefaults.standard.string(forKey: tokenKey) else { return }
        guard isSignedIn else { return }
        struct Body: Encodable { let token: String; let platform: String; let environment: String; let timezone: String; let app_version: String? }
        struct Out: Codable { let ok: Bool }
        #if DEBUG
        let env = "development"
        #else
        let env = "production"
        #endif
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        do {
            let _: Out = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/me/devices", method: .POST,
                body: try JSONEncoder().encode(Body(token: token, platform: "ios", environment: env,
                                                    timezone: TimeZone.current.identifier, app_version: version)),
                responseType: Out.self)
            pendingToken = nil
            UserDefaults.standard.set(true, forKey: registeredKey)
            Logger.info("PushRegistrar: device registered")
        } catch {
            Logger.warning("PushRegistrar: register failed: \(error)")
        }
    }

    /// Sign-out: the server stops sending to this device.
    func forget() async {
        UserDefaults.standard.set(false, forKey: registeredKey)
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        struct Out: Codable { let ok: Bool }
        _ = try? await NetworkService.shared.authenticatedRequest(endpoint: "/me/devices/\(token)", method: .DELETE, body: nil, responseType: Out.self) as Out
    }
}

final class HaloAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.didReceive(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.warning("Push: registration failed: \(error.localizedDescription)")
    }
}
