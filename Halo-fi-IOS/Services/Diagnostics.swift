//
//  Diagnostics.swift
//  Halo-fi-IOS
//
//  Fire-and-forget breadcrumbs to the server (2026-09-06). TestFlight has
//  no console, and the Money balance kept flipping on Liam's phone with
//  no way to see which write did it. Each account-map write and each
//  sign-in / sign-out now leaves one line in the backend log, keyed to
//  the user. Numbers only — never account names or tokens.
//

import Foundation

enum Diagnostics {
    static func send(_ event: String, _ fields: [String: String] = [:]) {
        struct Body: Encodable { let event: String; let fields: [String: String]; let app_version: String }
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        Task.detached(priority: .utility) {
            struct Out: Codable { let ok: Bool? }
            guard let data = try? JSONEncoder().encode(Body(event: event, fields: fields, app_version: version)) else { return }
            _ = try? await NetworkService.shared.authenticatedRequest(endpoint: "/me/diagnostics", method: .POST, body: data, responseType: Out.self)
        }
    }
}
