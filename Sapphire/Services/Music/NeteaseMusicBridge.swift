import AppKit
import ApplicationServices

/// Controls only the installed NetEase process. Authorization is enforced by AX
/// itself; a cached trust hint never authorizes an operation.
@MainActor
final class NeteaseMusicBridge {
    static let shared = NeteaseMusicBridge()
    enum Action: Sendable { case play, pause, next, previous, like, shuffle, repeatOff, repeatTrack, repeatAll }
    struct State: Sendable {
        var liked: Bool?
        var shuffled: Bool?
        var repeatMode: String?
    }
    enum Failure: Error, Equatable, Sendable {
        case permission, notRunning, unavailable, appBusy, timedOut, busy, disabled
    }
    struct Diagnostics: Sendable {
        let processTrusted: Bool
        let runningAppPath: String
        let sourceRevision: String?
        let targetProcessIdentifier: pid_t?
        let lastOperation: String?
        let lastFailure: Failure?
        let failureStage: String?
        let axErrorCode: Int32?
        let accessVerified: Bool?
        let checkedAt: Date?
    }

    private let executor: any NeteaseMusicExecuting
    private let processIdentifier: @MainActor () -> pid_t?
    private let trust: @MainActor () -> Bool
    private let prompt: @MainActor () -> Bool
    private let worker = DispatchQueue(label: "com.rocaka.sapphirecn.netease.ax", qos: .utility)
    private var trustHint: (value: Bool, expires: TimeInterval)?
    private var didPrompt = false
    private var commands: [Command] = []
    private var pendingRead: Read?
    private var executing = false
    private var outstandingCommands = 0
    private var readGeneration: UInt64 = 0
    private var sharedRead: (id: UUID, pid: pid_t, generation: UInt64, task: Task<State?, Never>)?
    private var lastDiagnostic: (operation: String, failure: Failure?, issue: NeteaseAXIssue?, accessVerified: Bool, checkedAt: Date)?

    private struct Command: Sendable {
        let id: UUID
        let pid: pid_t
        let action: Action
        let cancellation: NeteaseAXCancellation
        let continuation: CheckedContinuation<Void, Error>
    }
    private struct Read: Sendable {
        let pid: pid_t
        let generation: UInt64
        let continuation: CheckedContinuation<State?, Never>
    }

    init(executor: any NeteaseMusicExecuting = NeteaseAXExecutor(),
         processIdentifier: @escaping @MainActor () -> pid_t? = {
             NSRunningApplication.runningApplications(withBundleIdentifier: NeteaseMusicPolicy.bundleID).first?.processIdentifier
         },
         trust: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
         prompt: @escaping @MainActor () -> Bool = {
             let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
             return AXIsProcessTrustedWithOptions(options)
         }) {
        self.executor = executor
        self.processIdentifier = processIdentifier
        self.trust = trust
        self.prompt = prompt
    }

    /// A short-lived settings hint only. Do not use it to gate command execution.
    var isTrusted: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let trustHint, now < trustHint.expires { return trustHint.value }
        let value = trust()
        trustHint = (value, now + 1)
        return value
    }

    /// Refresh the settings hint on activation / trust notifications, never in a view body.
    @discardableResult
    func refreshPermissionHint() -> Bool {
        let value = trust()
        trustHint = (value, ProcessInfo.processInfo.systemUptime + 1)
        if value { didPrompt = false }
        return value
    }

    /// Explicit diagnostics reflect this running process rather than a cached
    /// permission hint. Neither method prompts or changes another app's state.
    func diagnosticSnapshot() -> Diagnostics {
        Diagnostics(processTrusted: refreshPermissionHint(), runningAppPath: Bundle.main.bundleURL.path,
            sourceRevision: Bundle.main.object(forInfoDictionaryKey: "SapphireSourceRevision") as? String,
            targetProcessIdentifier: processIdentifier(), lastOperation: lastDiagnostic?.operation,
            lastFailure: lastDiagnostic?.failure, failureStage: lastDiagnostic?.issue?.stage,
            axErrorCode: lastDiagnostic?.issue?.axErrorCode, accessVerified: lastDiagnostic?.accessVerified,
            checkedAt: lastDiagnostic?.checkedAt)
    }

    func checkConnection() async -> Diagnostics {
        guard processIdentifier() != nil else {
            lastDiagnostic = ("state", .notRunning, .init(failure: .notRunning, stage: "process.lookup", axErrorCode: nil), false, Date())
            return diagnosticSnapshot()
        }
        _ = await state()
        return diagnosticSnapshot()
    }

    /// Only explicit permission UI calls this method, never playback actions.
    func requestAccess() {
        if trust() {
            trustHint = (true, ProcessInfo.processInfo.systemUptime + 30)
            didPrompt = false
            return
        }
        guard !didPrompt else { return }
        didPrompt = true
        let value = prompt()
        trustHint = (value, ProcessInfo.processInfo.systemUptime + 1)
    }

    func perform(_ action: Action) async throws {
        guard let pid = processIdentifier() else { throw Failure.notRunning }
        let id = UUID()
        let cancellation = NeteaseAXCancellation()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !cancellation.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                guard outstandingCommands < 4 else { continuation.resume(throwing: Failure.busy); return }
                outstandingCommands += 1
                readGeneration &+= 1
                commands.append(Command(id: id, pid: pid, action: action, cancellation: cancellation, continuation: continuation))
                pump()
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in self?.cancelPending(id) }
        }
        try Task.checkCancellation()
        // Native menu callbacks update their marks asynchronously.
        try await Task.sleep(for: .milliseconds(150))
    }

    func state() async -> State? {
        guard let pid = processIdentifier() else { return nil }
        let generation = readGeneration
        if let sharedRead, sharedRead.pid == pid, sharedRead.generation == generation {
            let value = await sharedRead.task.value
            return generation == readGeneration ? value : nil
        }
        let id = UUID()
        let task = Task<State?, Never> { [weak self] in
            guard let self, !Task.isCancelled, generation == self.readGeneration else { return nil }
            return await withCheckedContinuation { continuation in
                // Admission remains generation-checked before replacing a newer read.
                guard generation == self.readGeneration else { continuation.resume(returning: nil); return }
                self.pendingRead?.continuation.resume(returning: nil)
                self.pendingRead = Read(pid: pid, generation: generation, continuation: continuation)
                self.pump()
            }
        }
        sharedRead = (id, pid, generation, task)
        let value = await task.value
        if sharedRead?.id == id { sharedRead = nil }
        return generation == readGeneration ? value : nil
    }

    /// Invalidate cached/coalesced state when the source or song changes. Commands
    /// already accepted retain their cancellation token and queue position.
    func invalidateState() {
        readGeneration &+= 1
        sharedRead = nil
        let obsolete = pendingRead
        pendingRead = nil
        obsolete?.continuation.resume(returning: nil)
    }

    private func cancelPending(_ id: UUID) {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        let command = commands.remove(at: index)
        outstandingCommands -= 1
        command.continuation.resume(throwing: CancellationError())
    }

    private func observeAccess<Value>(_ result: NeteaseAXResult<Value>, operation: String) {
        switch result.outcome {
        case .success:
            lastDiagnostic = (operation, nil, nil, result.accessVerified, Date())
        case .failure(let failure):
            lastDiagnostic = (operation, failure, result.issue, result.accessVerified, Date())
        case .cancelled: break
        }
        if case .failure(.permission) = result.outcome {
            trustHint = (false, ProcessInfo.processInfo.systemUptime + 1)
        } else if result.accessVerified {
            trustHint = (true, ProcessInfo.processInfo.systemUptime + 30)
            didPrompt = false
        }
    }

    private func pump() {
        guard !executing else { return }
        let executor = self.executor
        if !commands.isEmpty {
            let command = commands.removeFirst()
            executing = true
            worker.async(qos: .userInitiated) {
                let result = executor.perform(command.action, pid: command.pid, cancellation: command.cancellation)
                Task { @MainActor in
                    self.observeAccess(result, operation: String(describing: command.action))
                    self.outstandingCommands -= 1
                    self.executing = false
                    if command.cancellation.isCancelled { command.continuation.resume(throwing: CancellationError()) }
                    else {
                        switch result.outcome {
                        case .success: command.continuation.resume()
                        case .failure(let error): command.continuation.resume(throwing: error)
                        case .cancelled: command.continuation.resume(throwing: CancellationError())
                        }
                    }
                    self.pump()
                }
            }
        } else if let read = pendingRead {
            pendingRead = nil
            guard read.generation == readGeneration else { read.continuation.resume(returning: nil); pump(); return }
            executing = true
            worker.async {
                let result = executor.state(pid: read.pid)
                Task { @MainActor in
                    self.observeAccess(result, operation: "state")
                    self.executing = false
                    if case .success(let state) = result.outcome, read.generation == self.readGeneration {
                        read.continuation.resume(returning: state)
                    } else { read.continuation.resume(returning: nil) }
                    self.pump()
                }
            }
        }
    }
}

final class NeteaseAXCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

struct NeteaseAXIssue: Equatable, Sendable {
    let failure: NeteaseMusicBridge.Failure
    let stage: String
    let axErrorCode: Int32?
}

struct NeteaseAXResult<Value: Sendable>: Sendable {
    enum Outcome: Sendable { case success(Value), failure(NeteaseMusicBridge.Failure), cancelled }
    let outcome: Outcome
    let accessVerified: Bool
    let issue: NeteaseAXIssue?

    init(outcome: Outcome, accessVerified: Bool, issue: NeteaseAXIssue? = nil) {
        self.outcome = outcome
        self.accessVerified = accessVerified
        self.issue = issue
    }
}

protocol NeteaseMusicExecuting: Sendable {
    func perform(_ action: NeteaseMusicBridge.Action, pid: pid_t, cancellation: NeteaseAXCancellation) -> NeteaseAXResult<Void>
    func state(pid: pid_t) -> NeteaseAXResult<NeteaseMusicBridge.State>
}

struct NeteaseAXBudget {
    private var remaining: Int
    private let deadline: TimeInterval
    init(now: TimeInterval, duration: TimeInterval = 1.25, maximumQueries: Int = 90) {
        remaining = max(0, maximumQueries)
        deadline = now + max(0, duration)
    }
    mutating func consume(now: TimeInterval) -> Bool {
        guard remaining > 0, now < deadline else { return false }
        remaining -= 1
        return true
    }
}

enum NeteaseAXFailurePolicy {
    static func failure(for error: AXError) -> NeteaseMusicBridge.Failure? {
        switch error {
        case .success: nil
        case .apiDisabled: .permission
        case .cannotComplete: .appBusy
        default: .unavailable
        }
    }
}

struct NeteaseAXExecutor: NeteaseMusicExecuting {
    private final class Context {
        var budget = NeteaseAXBudget(now: ProcessInfo.processInfo.systemUptime)
        var accessVerified = false
        private(set) var issue: NeteaseAXIssue?
        private var stage = "request"
        let cancellation: NeteaseAXCancellation?
        init(cancellation: NeteaseAXCancellation? = nil) { self.cancellation = cancellation }
        func fail(_ failure: NeteaseMusicBridge.Failure, stage: String, axErrorCode: Int32? = nil) throws -> Never {
            issue = NeteaseAXIssue(failure: failure, stage: stage, axErrorCode: axErrorCode)
            throw failure
        }
        func prepare(_ element: AXUIElement, stage: String) throws {
            self.stage = stage
            issue = nil
            if cancellation?.isCancelled == true { throw CancellationError() }
            guard budget.consume(now: ProcessInfo.processInfo.systemUptime) else { try fail(.timedOut, stage: stage) }
            AXUIElementSetMessagingTimeout(element, 0.2)
        }
        func check(_ error: AXError) throws {
            switch error {
            case .success:
                accessVerified = true
            case .noValue, .attributeUnsupported:
                accessVerified = true
                issue = NeteaseAXIssue(failure: .unavailable, stage: stage, axErrorCode: error.rawValue)
            default: try fail(NeteaseAXFailurePolicy.failure(for: error) ?? .unavailable, stage: stage, axErrorCode: error.rawValue)
            }
        }
        func value(_ element: AXUIElement, _ key: String, stage: String) throws -> CFTypeRef? {
            try prepare(element, stage: stage)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
            try check(error)
            return value
        }
        func children(_ element: AXUIElement, stage: String) throws -> [AXUIElement] {
            try prepare(element, stage: stage)
            var values: CFArray?
            try check(AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, 48, &values))
            return values as? [AXUIElement] ?? []
        }
        func title(_ element: AXUIElement, stage: String) throws -> String { try value(element, kAXTitleAttribute, stage: stage) as? String ?? "" }
        func checked(_ element: AXUIElement?, stage: String) throws -> Bool? {
            guard let element else { return nil }
            try prepare(element, stage: stage)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXMenuItemMarkCharAttribute as CFString, &value)
            try check(error)
            if error == .noValue { return false }
            guard error == .success, let mark = value as? String else { return nil }
            return !mark.isEmpty
        }
    }

    private struct Menu {
        let items: [String: AXUIElement]
        let repeatItems: [String: AXUIElement]
        func item(_ aliases: [String], repeatMenu: Bool = false) -> AXUIElement? {
            let pool = repeatMenu ? repeatItems : items
            return aliases.lazy.compactMap { pool[$0] }.first
        }
    }

    private func indexedChildren(_ element: AXUIElement, stage: String, context: Context) throws -> [String: AXUIElement] {
        var result: [String: AXUIElement] = [:]
        for child in try context.children(element, stage: "\(stage).children") {
            let title = try context.title(child, stage: "\(stage).title")
            if !title.isEmpty, result[title] == nil { result[title] = child }
        }
        return result
    }

    private func menu(pid: pid_t, includeRepeat: Bool, context: Context) throws -> Menu {
        let app = AXUIElementCreateApplication(pid)
        guard let rawBar = try context.value(app, kAXMenuBarAttribute, stage: "application.AXMenuBar"), CFGetTypeID(rawBar) == AXUIElementGetTypeID() else {
            if let issue = context.issue { throw issue.failure }
            try context.fail(.unavailable, stage: "application.AXMenuBar.missing")
        }
        let bar = unsafeBitCast(rawBar, to: AXUIElement.self)
        var control: AXUIElement?
        let barItems = try context.children(bar, stage: "menuBar.AXChildren")
        guard !barItems.isEmpty else {
            if let issue = context.issue { throw issue.failure }
            try context.fail(.unavailable, stage: "menuBar.empty")
        }
        for item in barItems {
            if ["控制", "Controls", "Control", "播放控制"].contains(try context.title(item, stage: "menuBarItem.AXTitle")) { control = item; break }
        }
        guard let control else { try context.fail(.unavailable, stage: "controlMenu.notFound") }
        guard let menu = try context.children(control, stage: "controlMenu.AXChildren").first else {
            if let issue = context.issue { throw issue.failure }
            try context.fail(.unavailable, stage: "controlMenu.empty")
        }
        let items = try indexedChildren(menu, stage: "controlItem", context: context)
        guard !items.isEmpty else {
            if let issue = context.issue { throw issue.failure }
            try context.fail(.unavailable, stage: "controlMenu.items.empty")
        }
        var repeatItems: [String: AXUIElement] = [:]
        if includeRepeat, let repeatItem = ["循环播放", "Repeat"].compactMap({ items[$0] }).first,
           let submenu = try context.children(repeatItem, stage: "repeatMenu.AXChildren").first {
            repeatItems = try indexedChildren(submenu, stage: "repeatItem", context: context)
        }
        return Menu(items: items, repeatItems: repeatItems)
    }

    func perform(_ action: NeteaseMusicBridge.Action, pid: pid_t, cancellation: NeteaseAXCancellation) -> NeteaseAXResult<Void> {
        let context = Context(cancellation: cancellation)
        do {
            let isRepeat: Bool
            switch action { case .repeatOff, .repeatTrack, .repeatAll: isRepeat = true; default: isRepeat = false }
            let menu = try menu(pid: pid, includeRepeat: isRepeat, context: context)
            let aliases: [String]
            let alreadySet: AXUIElement?
            switch action {
            case .play: aliases = ["播放", "Play"]; alreadySet = menu.item(["暂停", "Pause"])
            case .pause: aliases = ["暂停", "Pause"]; alreadySet = menu.item(["播放", "Play"])
            case .next: aliases = ["下一个", "下一首", "Next", "Next Track"]; alreadySet = nil
            case .previous: aliases = ["上一个", "上一首", "Previous", "Previous Track"]; alreadySet = nil
            case .like: aliases = ["取消喜欢", "取消喜欢歌曲", "Unlike Song", "Dislike", "喜欢歌曲", "喜欢", "Like Song", "Like"]; alreadySet = nil
            case .shuffle: aliases = ["随机播放", "Shuffle"]; alreadySet = nil
            case .repeatOff: aliases = ["关", "关闭", "Off"]; alreadySet = nil
            case .repeatTrack: aliases = ["单曲", "One", "Repeat One"]; alreadySet = nil
            case .repeatAll: aliases = ["全部", "All", "Repeat All"]; alreadySet = nil
            }
            guard let item = alreadySet ?? menu.item(aliases, repeatMenu: isRepeat) else {
                try context.fail(.unavailable, stage: "command.\(action).menuItem.notFound")
            }
            guard try context.value(item, kAXEnabledAttribute, stage: "command.\(action).AXEnabled") as? Bool == true else {
                if let issue = context.issue { throw issue.failure }
                try context.fail(.disabled, stage: "command.\(action).AXEnabled.false")
            }
            if alreadySet == nil {
                try context.prepare(item, stage: "command.\(action).AXPress")
                try context.check(AXUIElementPerformAction(item, kAXPressAction as CFString))
            }
            return NeteaseAXResult(outcome: .success(()), accessVerified: context.accessVerified)
        } catch is CancellationError {
            return NeteaseAXResult(outcome: .cancelled, accessVerified: context.accessVerified)
        } catch {
            return NeteaseAXResult(outcome: .failure((error as? NeteaseMusicBridge.Failure) ?? .unavailable), accessVerified: context.accessVerified, issue: context.issue)
        }
    }

    func state(pid: pid_t) -> NeteaseAXResult<NeteaseMusicBridge.State> {
        let context = Context()
        do {
            let menu = try menu(pid: pid, includeRepeat: true, context: context)
            var state = NeteaseMusicBridge.State()
            if menu.item(["取消喜欢", "取消喜欢歌曲", "Unlike Song", "Dislike"]) != nil { state.liked = true }
            else { state.liked = try context.checked(menu.item(["喜欢歌曲", "喜欢", "Like Song", "Like"]), stage: "state.like.AXMenuItemMarkChar") }
            state.shuffled = try context.checked(menu.item(["随机播放", "Shuffle"]), stage: "state.shuffle.AXMenuItemMarkChar")
            for (aliases, mode) in [(["关", "关闭", "Off"], "off"), (["单曲", "One", "Repeat One"], "track"), (["全部", "All", "Repeat All"], "context")] {
                if try context.checked(menu.item(aliases, repeatMenu: true), stage: "state.repeat.\(mode).AXMenuItemMarkChar") == true { state.repeatMode = mode; break }
            }
            return NeteaseAXResult(outcome: .success(state), accessVerified: context.accessVerified)
        } catch {
            return NeteaseAXResult(outcome: .failure((error as? NeteaseMusicBridge.Failure) ?? .unavailable), accessVerified: context.accessVerified, issue: context.issue)
        }
    }
}
