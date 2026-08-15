import Foundation

/// Coalesces repeated refresh requests while one diff load is already running.
struct DiffReloadState {
    private var isRunning = false
    private var isPending = false

    mutating func request() -> Bool {
        guard !isRunning else {
            isPending = true
            return false
        }
        isRunning = true
        return true
    }

    mutating func cancel() {
        isPending = false
    }

    /// Returns whether one coalesced request should start now.
    mutating func complete() -> Bool {
        isRunning = false
        defer { isPending = false }
        return isPending
    }
}

/// Lets synchronous file reads notice cancellation between chunks. Git work
/// also observes the enclosing Swift task through `BoundedProcess`.
nonisolated final class DiffReloadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}
