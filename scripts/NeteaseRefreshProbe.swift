import Foundation

@MainActor private final class ProbeGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@main struct NeteaseRefreshProbe {
    @MainActor static func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<2_000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Refresh coordinator failed to make progress")
    }

    @MainActor static func main() async throws {
        precondition(!NeteaseRefreshPolicy.shouldStart(selected: true, visible: false, forced: false, inFlight: false, lastStarted: nil, now: 10))
        precondition(NeteaseRefreshPolicy.shouldStart(selected: true, visible: false, forced: true, inFlight: false, lastStarted: 10, now: 10))
        precondition(!NeteaseRefreshPolicy.shouldStart(selected: false, visible: true, forced: true, inFlight: false, lastStarted: nil, now: 10))
        precondition(!NeteaseRefreshPolicy.shouldStart(selected: true, visible: true, forced: true, inFlight: true, lastStarted: nil, now: 10))
        let first = ProbeGate()
        let second = ProbeGate()
        var reads = 0
        var now: TimeInterval = 100
        let coordinator = NeteaseStateRefreshCoordinator(clock: { now }) {
            reads += 1
            if reads == 1 { await first.wait() }
            if reads == 2 { await second.wait() }
        }
        precondition(coordinator.schedule(selected: true, visible: false) == nil)
        let initial = coordinator.schedule(selected: true, visible: false, force: true)!
        try await waitUntil { reads == 1 }
        for _ in 0..<1_000 { coordinator.schedule(selected: true, visible: true, force: true) }
        precondition(reads == 1, "Metadata/command bursts must share one in-flight read")
        first.open()
        try await waitUntil { reads == 2 }
        precondition(coordinator.isRunning)
        second.open()
        await initial.value
        precondition(reads == 2 && !coordinator.isRunning, "Forced requests during a read need exactly one fresh confirmation pass")
        now = 101
        precondition(coordinator.schedule(selected: true, visible: true) == nil)
        now = 102
        let visibleRead = coordinator.schedule(selected: true, visible: true)!
        await visibleRead.value
        precondition(reads == 3)
        now = 200
        for _ in 0..<1_000 { precondition(coordinator.schedule(selected: true, visible: false) == nil) }
        precondition(reads == 3, "Hidden player metadata must not poll the AX menu")

        let oldGate = ProbeGate()
        let newGate = ProbeGate()
        var switchedReads = 0
        let switched = NeteaseStateRefreshCoordinator {
            switchedReads += 1
            let pass = switchedReads
            if pass == 1 { await oldGate.wait() }
            if pass == 2 { await newGate.wait() }
        }
        let old = switched.schedule(selected: true, visible: true, force: true)!
        try await waitUntil { switchedReads == 1 }
        switched.cancel()
        let new = switched.schedule(selected: true, visible: true, force: true)!
        try await waitUntil { switchedReads == 2 }
        oldGate.open()
        await old.value
        precondition(switched.isRunning, "An old completion must not clear the new source's task")
        newGate.open()
        await new.value
        precondition(!switched.isRunning)
        print("NetEase refresh: one in-flight read, coalesced force confirmation, no hidden polling and safe source changes passed")
    }
}
