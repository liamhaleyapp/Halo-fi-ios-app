import Foundation

/// Invalidates work started before sign-out or a new sign-in. The lock makes
/// checking ownership and saving credentials one operation across executors.
final class SessionLifetime: @unchecked Sendable {
    static let shared = SessionLifetime()
    private let lock = NSRecursiveLock()
    private var generation = UUID()

    var current: UUID {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func isCurrent(_ expected: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expected
    }

    @discardableResult
    func invalidate<T>(perform operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        generation = UUID()
        return try operation()
    }

    func check(_ expected: UUID) throws {
        try withCurrent(expected) { }
    }

    func withCurrent<T>(_ expected: UUID, perform operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expected else { throw CancellationError() }
        return try operation()
    }
}


/// A bounded, device-local history survives an app restart or forced sign-out.
/// Only fixed event names, timestamps and build numbers; never credentials or user data.
enum AuthSessionDiagnostics {
    enum Event: String, Codable {
        case refreshRejected, refreshDeferred, storageWriteFailed, storageReadFailed
        case restorationDeferred, restorationSucceeded, signedOut
    }
    struct Entry: Codable {
        let event: Event
        let date: Date
        let build: String
    }
    private static let lock = NSLock()
    static let storageKey = "auth_session_diagnostics_v1"

    static func record(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        let entries = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let updated = Array((entries + [Entry(event: event, date: Date(), build: "\(version) (\(build))")]).suffix(30))
        if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: storageKey) }
    }
}
