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
    func invalidate<T>(perform operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        generation = UUID()
        return operation()
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
