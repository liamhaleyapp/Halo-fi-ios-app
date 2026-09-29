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
//  2026-09-29: a tester froze the app and nobody could say where. Every
//  breadcrumb now carries the screen the user is on, and MetricKit's crash
//  and hang diagnostics (delivered by iOS on the next launch) are forwarded
//  with the screen that was showing when the app died.
//

import Foundation
import MetricKit

enum Diagnostics {
    private static let screenKey = "diagnostics.lastScreen"
    private static let pendingDirectory = "DiagnosticReports"

    /// The screen showing now, kept in UserDefaults so it survives a crash
    /// and can be attached to the report iOS hands back after relaunch.
    private(set) static var lastScreen: String = UserDefaults.standard.string(forKey: screenKey) ?? "launch"
    /// What was on screen when the previous process ended.
    private static var screenBeforeLaunch: String = UserDefaults.standard.string(forKey: screenKey) ?? "launch"

    static func screen(_ name: String) {
        guard name != lastScreen else { return }
        lastScreen = name
        UserDefaults.standard.set(name, forKey: screenKey)
    }

    static func send(_ event: String, _ fields: [String: String] = [:]) {
        struct Body: Encodable { let event: String; let fields: [String: String]; let app_version: String }
        var fields = fields
        fields["screen"] = lastScreen
        let sessionGeneration = SessionLifetime.shared.current
        Task.detached(priority: .utility) {
            guard SessionLifetime.shared.isCurrent(sessionGeneration) else { return }
            struct Out: Codable { let ok: Bool? }
            guard let data = try? JSONEncoder().encode(Body(event: event, fields: fields, app_version: appVersion)) else { return }
            _ = try? await NetworkService.shared.authenticatedRequest(endpoint: "/me/diagnostics", method: .POST, body: data, responseType: Out.self)
            // A signed-in session is the first chance to deliver reports
            // that arrived before there was a token to send them with.
            if event == "sign_in" { await Reporter.flush() }
        }
    }

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
    }

    /// Call once at launch. Diagnostics from the previous run arrive here
    /// shortly after; they are written to disk first so nothing is lost if
    /// there is no session yet, then sent on the next sign-in.
    static func install() {
        screenBeforeLaunch = UserDefaults.standard.string(forKey: screenKey) ?? "launch"
        screen("launch")
        MXMetricManager.shared.add(Reporter.shared)
    }

    // MARK: - MetricKit

    final class Reporter: NSObject, MXMetricManagerSubscriber {
        static let shared = Reporter()

        struct Report: Codable {
            let kind: String
            let fields: [String: String]
            let app_version: String
            let report: String?
        }

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            var reports: [Report] = []
            for payload in payloads {
                let when = ISO8601DateFormatter().string(from: payload.timeStampEnd)
                for crash in payload.crashDiagnostics ?? [] {
                    var fields = base(crash.metaData, when: when)
                    fields["exception_type"] = crash.exceptionType.map { "\($0)" } ?? ""
                    fields["exception_code"] = crash.exceptionCode.map { "\($0)" } ?? ""
                    fields["signal"] = crash.signal.map { "\($0)" } ?? ""
                    fields["termination_reason"] = crash.terminationReason ?? ""
                    reports.append(Report(kind: "crash", fields: fields, app_version: Diagnostics.appVersion,
                                          report: tree(crash.callStackTree)))
                }
                for hang in payload.hangDiagnostics ?? [] {
                    var fields = base(hang.metaData, when: when)
                    fields["hang_seconds"] = String(format: "%.1f", hang.hangDuration.converted(to: .seconds).value)
                    reports.append(Report(kind: "hang", fields: fields, app_version: Diagnostics.appVersion,
                                          report: tree(hang.callStackTree)))
                }
            }
            guard !reports.isEmpty else { return }
            Self.store(reports)
            Task.detached(priority: .utility) { await Reporter.flush() }
        }

        private func base(_ meta: MXMetaData, when: String) -> [String: String] {
            ["reported_at": when, "os": meta.osVersion, "device": meta.deviceType,
             "build": meta.applicationBuildVersion, "last_screen": Diagnostics.screenBeforeLaunch,
             "screen_now": Diagnostics.lastScreen]
        }

        /// The symbolicated frames, capped well under the server's limit.
        private func tree(_ tree: MXCallStackTree) -> String? {
            guard let json = String(data: tree.jsonRepresentation(), encoding: .utf8) else { return nil }
            return json.count > 350_000 ? String(json.prefix(350_000)) : json
        }

        // MARK: pending queue on disk

        private static var directory: URL? {
            guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            let dir = base.appendingPathComponent(Diagnostics.pendingDirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        private static func store(_ reports: [Report]) {
            guard let dir = directory else { return }
            for report in reports {
                guard let data = try? JSONEncoder().encode(report) else { continue }
                try? data.write(to: dir.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
            }
        }

        static func flush() async {
            guard let dir = directory,
                  let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            struct Out: Codable { let ok: Bool? }
            for file in files.prefix(10) {
                guard let data = try? Data(contentsOf: file) else { continue }
                if let out = try? await NetworkService.shared.authenticatedRequest(endpoint: "/me/diagnostics/report", method: .POST, body: data, responseType: Out.self),
                   out.ok == true {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
