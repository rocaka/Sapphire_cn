import AppKit
import ApplicationServices
import Foundation

private final class FakeExecutor: NeteaseMusicExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var failure: NeteaseMusicBridge.Failure?
    private var blockedFirst = false
    private let blockKind: String?
    private let issue: NeteaseAXIssue?
    let release = DispatchSemaphore(value: 0)
    init(failure: NeteaseMusicBridge.Failure? = nil, blockKind: String? = nil, issue: NeteaseAXIssue? = nil) {
        self.failure = failure
        self.blockKind = blockKind
        self.issue = issue
    }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    func setFailure(_ value: NeteaseMusicBridge.Failure?) { lock.lock(); failure = value; lock.unlock() }
    private func enter(_ kind: String) -> NeteaseMusicBridge.Failure? {
        lock.lock()
        recorded.append(kind)
        let shouldBlock = kind == blockKind && !blockedFirst
        if shouldBlock { blockedFirst = true }
        let value = failure
        lock.unlock()
        if shouldBlock { precondition(release.wait(timeout: .now() + 5) == .success, "Test worker was never released") }
        return value
    }
    func perform(_ action: NeteaseMusicBridge.Action, pid: pid_t, cancellation: NeteaseAXCancellation) -> NeteaseAXResult<Void> {
        let error = enter(String(describing: action))
        if cancellation.isCancelled { return .init(outcome: .cancelled, accessVerified: false) }
        if let error { return .init(outcome: .failure(error), accessVerified: error != .permission, issue: issue) }
        return .init(outcome: .success(()), accessVerified: true)
    }
    func state(pid: pid_t) -> NeteaseAXResult<NeteaseMusicBridge.State> {
        if let error = enter("read") { return .init(outcome: .failure(error), accessVerified: error != .permission, issue: issue) }
        return .init(outcome: .success(.init(liked: true, shuffled: false, repeatMode: "off")), accessVerified: true)
    }
}

@main struct NeteaseBridgeProbe {
    @MainActor private static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !predicate() {
            precondition(ProcessInfo.processInfo.systemUptime < deadline, "Timed out waiting for test work")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor static func main() async throws {
        precondition(NeteaseAXFailurePolicy.failure(for: .apiDisabled) == .permission)
        precondition(NeteaseAXFailurePolicy.failure(for: .cannotComplete) == .appBusy)
        precondition(NeteaseAXFailurePolicy.failure(for: .attributeUnsupported) == .unavailable)
        var budget = NeteaseAXBudget(now: 0, duration: 1, maximumQueries: 2)
        precondition(budget.consume(now: 0) && budget.consume(now: 0.5) && !budget.consume(now: 0.6))
        var expired = NeteaseAXBudget(now: 0, duration: 1)
        precondition(!expired.consume(now: 1))

        var prompts = 0
        let deniedExecutor = FakeExecutor(failure: .permission,
            issue: .init(failure: .permission, stage: "application.AXMenuBar", axErrorCode: AXError.apiDisabled.rawValue))
        let denied = NeteaseMusicBridge(executor: deniedExecutor, processIdentifier: { 123 }, trust: { true }, prompt: { prompts += 1; return false })
        let deniedDiagnostic = await denied.checkConnection()
        precondition(deniedDiagnostic.processTrusted && deniedDiagnostic.lastFailure == .permission,
            "Diagnostics must show actual raw trust independently of an AX rejection")
        precondition(deniedDiagnostic.lastOperation == "state" && deniedDiagnostic.failureStage == "application.AXMenuBar")
        precondition(deniedDiagnostic.axErrorCode == -25211 && deniedDiagnostic.accessVerified == false)
        precondition(deniedDiagnostic.runningAppPath == Bundle.main.bundleURL.path && deniedDiagnostic.targetProcessIdentifier == 123)
        precondition(deniedDiagnostic.checkedAt != nil && prompts == 0, "Connection diagnostics must never prompt")
        let unsupportedExecutor = FakeExecutor(failure: .unavailable,
            issue: .init(failure: .unavailable, stage: "application.AXMenuBar", axErrorCode: AXError.attributeUnsupported.rawValue))
        let unsupported = NeteaseMusicBridge(executor: unsupportedExecutor, processIdentifier: { 123 }, trust: { true }, prompt: { prompts += 1; return false })
        let unsupportedDiagnostic = await unsupported.checkConnection()
        precondition(unsupportedDiagnostic.lastFailure == .unavailable && unsupportedDiagnostic.axErrorCode == -25205,
            "An unavailable AXMenuBar must not be presented as a permission failure")
        let absentExecutor = FakeExecutor()
        let absent = NeteaseMusicBridge(executor: absentExecutor, processIdentifier: { nil }, trust: { true }, prompt: { prompts += 1; return false })
        let absentDiagnostic = await absent.checkConnection()
        precondition(absentDiagnostic.lastFailure == .notRunning && absentDiagnostic.failureStage == "process.lookup")
        precondition(absentDiagnostic.axErrorCode == nil && absentExecutor.events.isEmpty && prompts == 0)

        let executor = FakeExecutor()
        let bridge = NeteaseMusicBridge(executor: executor, processIdentifier: { 123 }, trust: { false }, prompt: { prompts += 1; return false })
        try await bridge.perform(.play)
        precondition(bridge.isTrusted, "Actual AX success must work even when a trust hint was stale")
        precondition(prompts == 0, "Playback actions must never prompt")
        executor.setFailure(.permission)
        for _ in 0..<3 {
            do { try await bridge.perform(.like); preconditionFailure("Permission error expected") }
            catch NeteaseMusicBridge.Failure.permission { }
        }
        precondition(prompts == 0, "Repeated actions must not reopen permission prompts")
        bridge.requestAccess(); bridge.requestAccess()
        precondition(prompts == 1, "Explicit permission requests are limited within the denied session")
        executor.setFailure(.appBusy)
        do { try await bridge.perform(.pause); preconditionFailure("Busy error expected") }
        catch NeteaseMusicBridge.Failure.appBusy { }

        let stateExecutor = FakeExecutor(blockKind: "read")
        let states = NeteaseMusicBridge(executor: stateExecutor, processIdentifier: { 123 }, trust: { false }, prompt: { false })
        let reads = (0..<20).map { _ in Task { await states.state() } }
        try await waitUntil { stateExecutor.events.count == 1 }
        for _ in 0..<20 { await Task.yield() }
        stateExecutor.release.signal()
        for task in reads { let state = await task.value; precondition(state?.liked == true) }
        precondition(stateExecutor.events == ["read"], "Concurrent state requests must share one operation")

        let orderedExecutor = FakeExecutor(blockKind: "read")
        let ordered = NeteaseMusicBridge(executor: orderedExecutor, processIdentifier: { 123 }, trust: { false }, prompt: { false })
        let staleRead = Task { await ordered.state() }
        try await waitUntil { orderedExecutor.events == ["read"] }
        var commandsStarted = 0
        let next = Task { commandsStarted += 1; try await ordered.perform(.next) }
        try await waitUntil { commandsStarted == 1 }
        for _ in 0..<10 { await Task.yield() }
        let previous = Task { commandsStarted += 1; try await ordered.perform(.previous) }
        try await waitUntil { commandsStarted == 2 }
        for _ in 0..<10 { await Task.yield() }
        let freshRead = Task { await ordered.state() }
        for _ in 0..<10 { await Task.yield() }
        orderedExecutor.release.signal()
        try await next.value; try await previous.value
        let staleState = await staleRead.value
        let freshState = await freshRead.value
        precondition(staleState == nil, "A pre-command state must not overwrite the command result")
        precondition(freshState?.liked == true)
        precondition(orderedExecutor.events == ["read", "next", "previous", "read"], "Commands must take priority over pending reads")

        let invalidationExecutor = FakeExecutor(blockKind: "next")
        let invalidated = NeteaseMusicBridge(executor: invalidationExecutor, processIdentifier: { 123 }, trust: { false }, prompt: { false })
        let preservedCommand = Task { try await invalidated.perform(.next) }
        try await waitUntil { invalidationExecutor.events == ["next"] }
        var oldEntered = false
        var oldFinished = false
        let oldSong = Task(priority: .background) {
            oldEntered = true
            let result = await invalidated.state()
            oldFinished = true
            return result
        }
        try await waitUntil { oldEntered }
        invalidated.invalidateState()
        // Same PID, new song: this request must not reuse or be replaced by the old read.
        let newSong = Task(priority: .userInitiated) { await invalidated.state() }
        try await waitUntil { oldFinished }
        let oldSongState = await oldSong.value
        precondition(oldSongState == nil, "Invalidation must release old pending/coalesced readers")
        invalidationExecutor.release.signal()
        try await preservedCommand.value
        let newSongState = await newSong.value
        precondition(newSongState?.liked == true, "The new song must receive its own snapshot")
        precondition(invalidationExecutor.events == ["next", "read"], "State invalidation must not cancel or duplicate actions")

        let boundedExecutor = FakeExecutor(blockKind: "next")
        let bounded = NeteaseMusicBridge(executor: boundedExecutor, processIdentifier: { 123 }, trust: { false }, prompt: { false })
        let first = Task { try await bounded.perform(.next) }
        try await waitUntil { boundedExecutor.events.count == 1 }
        var started = 0
        let burst = (0..<8).map { _ in Task { () -> NeteaseMusicBridge.Failure? in
            started += 1
            do { try await bounded.perform(.like); return nil }
            catch { return error as? NeteaseMusicBridge.Failure }
        } }
        try await waitUntil { started == 8 }
        for _ in 0..<10 { await Task.yield() }
        boundedExecutor.release.signal()
        try await first.value
        var busy = 0
        for task in burst { if await task.value == .busy { busy += 1 } }
        precondition(busy == 5 && boundedExecutor.events.count == 4, "The action queue must be bounded and accepted toggles must execute once")
        print("NetEase AX bridge: no automatic prompts, raw trust / AX failure diagnostics, shared reads, action priority, stale-state rejection, song invalidation and bounded queue passed")
    }
}
