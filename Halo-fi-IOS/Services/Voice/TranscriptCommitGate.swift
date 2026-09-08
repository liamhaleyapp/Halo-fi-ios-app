import Foundation

/// Registers before sending a commit. Timeout and cancellation resume the same
/// continuation, so neither can leave a task group waiting forever.
@MainActor
final class TranscriptCommitGate {
    private var waiter: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var generation = UUID()

    func wait(timeout: TimeInterval = 2, send: @escaping @MainActor () async throws -> Void) async -> Bool {
        guard waiter == nil, !Task.isCancelled else { return false }
        let token = UUID()
        generation = token
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter = continuation
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    self?.finish(false, token: token)
                }
                sendTask = Task { [weak self] in
                    do { try await send() } catch { self?.finish(false, token: token) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(false, token: token) }
        }
    }

    func complete() { finish(true, token: generation) }
    func cancel() { finish(false, token: generation) }

    private func finish(_ success: Bool, token: UUID) {
        guard generation == token, let continuation = waiter else { return }
        waiter = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        sendTask?.cancel()
        sendTask = nil
        continuation.resume(returning: success)
    }
}
