import Foundation

enum NeteaseRefreshPolicy {
    static let visibleInterval: TimeInterval = 2

    static func shouldStart(selected: Bool, visible: Bool, forced: Bool, inFlight: Bool,
                            lastStarted: TimeInterval?, now: TimeInterval) -> Bool {
        guard selected, !inFlight else { return false }
        if forced { return true }
        guard visible, now.isFinite else { return false }
        guard let lastStarted, lastStarted.isFinite else { return true }
        return now < lastStarted || now - lastStarted >= visibleInterval
    }
}

/// One task for the entire read sequence. Forced reads arriving during a read
/// coalesce into one fresh pass, so an action's confirmation is never lost.
@MainActor
final class NeteaseStateRefreshCoordinator {
    private let operation: @MainActor () async -> Void
    private let clock: @MainActor () -> TimeInterval
    private var task: Task<Void, Never>?
    private var forcedPending = false
    private var generation: UInt64 = 0
    private var lastStarted: TimeInterval?

    init(clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         operation: @escaping @MainActor () async -> Void) {
        self.clock = clock
        self.operation = operation
    }

    var isRunning: Bool { task != nil }

    @discardableResult
    func schedule(selected: Bool, visible: Bool, force: Bool = false) -> Task<Void, Never>? {
        guard selected else { return nil }
        if let task {
            if force { forcedPending = true }
            return task
        }
        guard NeteaseRefreshPolicy.shouldStart(selected: selected, visible: visible, forced: force,
            inFlight: false, lastStarted: lastStarted, now: clock()) else { return nil }
        let token = generation
        let next = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == token { task = nil; forcedPending = false }
            }
            repeat {
                guard !Task.isCancelled, generation == token else { return }
                forcedPending = false
                lastStarted = clock()
                await operation()
                guard !Task.isCancelled, generation == token else { return }
            } while forcedPending
        }
        task = next
        return next
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        forcedPending = false
        lastStarted = nil
    }
}
