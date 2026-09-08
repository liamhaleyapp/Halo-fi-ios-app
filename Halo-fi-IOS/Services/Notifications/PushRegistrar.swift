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

@MainActor
final class PushRegistrar: NSObject {
    static let shared = PushRegistrar()

    private let tokenKey = "pushDeviceToken.v1"
    private let registeredKey = "pushDeviceRegistered.v1"
    private var pendingToken: String?
    private let network: NetworkService
    private let defaults: UserDefaults
    private let lifetime: SessionLifetime
    private let unregister: @MainActor () -> Void
    private var operation: Task<Void, Never>?

    init(network: NetworkService = .shared, defaults: UserDefaults = .standard,
         lifetime: SessionLifetime = .shared,
         unregister: (@MainActor () -> Void)? = nil) {
        self.network = network
        self.defaults = defaults
        self.lifetime = lifetime
        self.unregister = unregister ?? { UIApplication.shared.unregisterForRemoteNotifications() }
        super.init()
    }
    /// True once /me/devices accepted this device: the server pushes, the
    /// app stops scheduling local digests.
    var isRegistered: Bool { defaults.bool(forKey: registeredKey) }

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
        didSet { if isSignedIn { registerIfAllowed(); Task { await sendIfSignedIn() } } }
    }

    /// Ask iOS for a token if the user already allowed notifications.
    func registerIfAllowed() {
        let generation = lifetime.current
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard isSignedIn, lifetime.isCurrent(generation), !UITestArchetype.isActive else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// From the app delegate: the token as hex.
    func didReceive(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: tokenKey)
        pendingToken = token
        if !isSignedIn { unregister() }
        Task { await sendIfSignedIn() }
    }

    /// Call after sign-in too: a token that arrived before the session was
    /// restored is sent once the user is known.
    func sendIfSignedIn() async {
        guard !UITestArchetype.isActive, isSignedIn,
              let token = pendingToken ?? defaults.string(forKey: tokenKey) else { return }
        let generation = lifetime.current
        let previous = operation
        let task = Task { [self] in
            await previous?.value
            guard isSignedIn, lifetime.isCurrent(generation) else { return }
            struct Body: Encodable { let token: String; let platform: String; let environment: String; let timezone: String; let app_version: String? }
            struct Out: Codable { let ok: Bool }
            #if DEBUG
            let env = "development"
            #else
            let env = "production"
            #endif
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            do {
                let response: Out = try await network.authenticatedRequest(
                    endpoint: "/me/devices", method: .POST,
                    body: try JSONEncoder().encode(Body(token: token, platform: "ios", environment: env,
                                                        timezone: TimeZone.current.identifier, app_version: version)),
                    responseType: Out.self)
                guard response.ok, isSignedIn, lifetime.isCurrent(generation),
                      defaults.string(forKey: tokenKey) == token else { return }
                pendingToken = nil
                defaults.set(true, forKey: registeredKey)
                Logger.info("PushRegistrar: device registered")
            } catch {
                Logger.warning("PushRegistrar: register failed: \(error)")
            }
        }
        operation = task
        await task.value
    }

    /// Capture credentials synchronously, before UserManager clears them.
    /// Serialize after any old registration and before the next account's.
    @discardableResult
    func forget() -> Task<Void, Never> {
        isSignedIn = false
        defaults.set(false, forKey: registeredKey)
        unregister()
        let request = defaults.string(forKey: tokenKey).flatMap { try? network.prepareDeviceRevocation(deviceToken: $0) }
        let previous = operation
        let task = Task { [network] in
            await previous?.value
            guard let request else { return }
            do { try await network.sendDeviceRevocation(request) }
            catch { Logger.warning("PushRegistrar: device revocation could not reach the server") }
        }
        operation = task
        return task
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
