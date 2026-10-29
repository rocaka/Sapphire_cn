#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

/// Finder performs its normal Copy / Move Item Here commands. This class never
/// moves or removes a file itself and never replaces clipboard contents.
final class FinderCutPasteManager: ObservableObject, @unchecked Sendable {
    static let shared = FinderCutPasteManager()
    @MainActor @Published private(set) var status: String?
    @MainActor @Published private(set) var isActive = false
    private let lock = NSLock()
    private var state = State()
    private struct State {
        var enabled = false
        var finderPID: pid_t?
        var generation: UInt64 = 0
        var policy = PublicFinderCutPolicy()
        var copyDeadline: TimeInterval?
        var mappedKeys: [Int64: (key: Int64, option: Bool)] = [:]
    }
    @MainActor private var token: GlobalEventTap.Token?
    @MainActor private var changes: AnyCancellable?
    @MainActor private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @MainActor private var copyChecks: [DispatchWorkItem] = []
    @MainActor private var configuredEnabled = false
    @MainActor private var suspended = false
    private init() {}

    @MainActor func start() {
        guard changes == nil else { return }
        token = GlobalEventTap.shared.register(name: "PublicFinderCutPaste",
            mask: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue),
            priority: EventTapPriority.transform, enabled: false, reset: { [weak self] in self?.invalidate() }) { [weak self] type, event in
                self?.handle(type: type, event: event) ?? .pass
            }
        AccessibilityTrustMonitor.shared.register(name: "PublicFinderCutPaste", owner: self,
            teardown: { $0.configure() }, reinstall: { $0.configure() })
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { $0.configure() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { $0.suspended = true; $0.configure() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.suspended = false; $0.configure() }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { $0.removeTap() }
        changes = SettingsModel.shared.changes(of: { $0.clipboardFinderCutPasteEnabled })
            .prepend(SettingsModel.shared.current.clipboardFinderCutPasteEnabled)
            .sink { [weak self] enabled in self?.configuredEnabled = enabled; self?.configure() }
    }

    @MainActor private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping (FinderCutPasteManager) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }))
    }

    @MainActor private func configure() {
        cancelChecks()
        let trusted = AccessibilityTrustMonitor.isCurrentlyTrusted()
        let enabled = configuredEnabled && trusted && !suspended
        let app = NSWorkspace.shared.frontmostApplication
        lock.lock()
        state = State(enabled: enabled, finderPID: app?.bundleIdentifier == "com.apple.finder" ? app?.processIdentifier : nil,
            generation: state.generation &+ 1)
        lock.unlock()
        if let token { GlobalEventTap.shared.setEnabled(token, enabled) }
        isActive = enabled
        setStatus(configuredEnabled && !trusted ? "Finder cut and paste needs Accessibility access. Enable Sapphire in System Settings." : nil)
    }

    private func invalidate() {
        lock.lock()
        state.generation &+= 1
        state.policy.reset(); state.copyDeadline = nil; state.mappedKeys.removeAll()
        lock.unlock()
    }

    private static let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    private func handle(type: CGEventType, event: CGEvent) -> EventTapDecision {
        guard type == .keyDown || type == .keyUp else { return .pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        lock.lock()
        let snapshot = state
        if type == .keyUp { state.mappedKeys.removeValue(forKey: code) }
        lock.unlock()
        guard snapshot.enabled, let pid = snapshot.finderPID, AccessibilityTrustMonitor.isCurrentlyTrusted(), !IsSecureEventInputEnabled() else { return .pass }
        if type == .keyUp {
            guard snapshot.mappedKeys[code] != nil else { return .pass }
        } else {
            guard event.flags.intersection(Self.modifiers) == .maskCommand else { return .pass }
            if code == 8 { invalidate(); return .pass } // An ordinary Copy cancels a cut.
            guard code == 7 || code == 9, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return .pass }
            if code == 9, snapshot.policy.version == nil {
                // A fast paste before native Copy is confirmed stays a normal
                // Finder paste. Never ask a lazy pasteboard provider on this tap.
                invalidate(); return .pass
            }
        }
        let target = event.getIntegerValueField(.eventTargetUnixProcessID)
        guard PublicFinderCutPolicy.acceptsTarget(enabled: snapshot.enabled, finderPID: pid,
            focusedPID: Self.focusedApplicationPID(), eventTargetPID: target) else { invalidate(); return .pass }
        if type == .keyUp {
            guard let mapping = snapshot.mappedKeys[code] else { return .pass }
            return Self.replace(event, key: mapping.key, option: mapping.option)
        }
        guard let focused = PublicInputAX.element(Self.value(AXUIElementCreateApplication(pid), attribute: kAXFocusedUIElementAttribute)),
              let role = Self.value(focused, attribute: kAXRoleAttribute) as? String,
              ![kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            if code == 9 { invalidate() }
            return .pass
        }
        if code == 7 {
            guard let files = Self.selectedFiles(focused), !files.isEmpty else {
                report("Finder did not expose a small, verifiable file selection. The shortcut was left unchanged."); return .pass
            }
            let before = NSPasteboard.general.changeCount
            lock.lock()
            guard state.enabled, state.finderPID == pid, state.generation == snapshot.generation else { lock.unlock(); return .pass }
            state.policy.beginCopy(changeCount: before, files: files)
            state.copyDeadline = ProcessInfo.processInfo.systemUptime + 1
            let generation = state.generation
            lock.unlock()
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.scheduleCopyChecks(generation: generation) } }
            guard Self.focusedApplicationPID() == pid,
                  let currentFocus = PublicInputAX.element(Self.value(AXUIElementCreateApplication(pid), attribute: kAXFocusedUIElementAttribute)),
                  CFEqual(currentFocus, focused) else { invalidate(); return .pass }
            return finishKeyDown(event, originalKey: 7, key: 8, option: false, pid: pid, generation: snapshot.generation)
        }
        // Empty destination folders are valid; text fields (search / rename) were
        // excluded above. Clipboard identity is checked at the actual shortcut.
        let currentCount = NSPasteboard.general.changeCount
        lock.lock()
        guard state.enabled, state.finderPID == pid, state.generation == snapshot.generation else { lock.unlock(); return .pass }
        let current = state.policy.version.flatMap { $0.changeCount == currentCount ? $0 : nil }
        let move = state.policy.consume(current: current, finderActive: true)
        state.copyDeadline = nil
        lock.unlock()
        guard move else { return .pass }
        guard Self.focusedApplicationPID() == pid,
              let currentFocus = PublicInputAX.element(Self.value(AXUIElementCreateApplication(pid), attribute: kAXFocusedUIElementAttribute)),
              CFEqual(currentFocus, focused), NSPasteboard.general.changeCount == currentCount else { invalidate(); return .pass }
        return finishKeyDown(event, originalKey: 9, key: 9, option: true, pid: pid, generation: snapshot.generation)
    }

    /// Revalidate lifecycle after the final AX / pasteboard reads. Constructing
    /// the decision under this lock makes disable/reset and acceptance ordered.
    /// A release for an already accepted keyDown keeps its existing pairing path.
    private func finishKeyDown(_ event: CGEvent, originalKey: Int64, key: Int64, option: Bool, pid: pid_t, generation: UInt64) -> EventTapDecision {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted(), !IsSecureEventInputEnabled() else { invalidate(); return .pass }
        lock.lock()
        defer { lock.unlock() }
        guard state.enabled, state.finderPID == pid, state.generation == generation else { return .pass }
        let decision = Self.replace(event, key: key, option: option)
        if case .replace = decision {
            state.mappedKeys[originalKey] = (key, option)
        } else {
            state.policy.reset(); state.copyDeadline = nil
        }
        return decision
    }

    private static func replace(_ event: CGEvent, key: Int64, option: Bool) -> EventTapDecision {
        guard let replacement = event.copy() else { return .pass }
        replacement.setIntegerValueField(.keyboardEventKeycode, value: key)
        var characters: [UniChar] = [key == 8 ? 0x63 : 0x76]
        replacement.keyboardSetUnicodeString(stringLength: 1, unicodeString: &characters)
        if option { replacement.flags.insert(.maskAlternate) }
        return .replace(replacement)
    }

    /// This reads selection metadata only. Unknown views / ambiguous URLs fail
    /// closed. A large selection cannot monopolize the shared event-tap thread.
    private static func selectedFiles(_ focused: AXUIElement) -> [String]? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.045
        var container = focused
        var selection: [AXUIElement] = []
        for _ in 0..<3 {
            if let children = children(container, attribute: kAXSelectedChildrenAttribute, maximum: 128), !children.isEmpty { selection = children; break }
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let parent = PublicInputAX.element(value(container, attribute: kAXParentAttribute)) else { return nil }
            container = parent
        }
        guard !selection.isEmpty, selection.count <= 128 else { return nil }
        var files: [String] = []
        for selected in selection {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var values = Set<String>()
            func readURL(_ item: AXUIElement) {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return }
                if let raw = value(item, attribute: kAXURLAttribute) {
                    let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
                    if let url, url.isFileURL { values.insert(url.standardizedFileURL.absoluteString) }
                }
            }
            readURL(selected)
            if values.isEmpty, let children = children(selected, attribute: kAXChildrenAttribute, maximum: 8) {
                for child in children { readURL(child) }
            }
            guard values.count == 1, let file = values.first else { return nil }
            files.append(file)
        }
        return files
    }

    private static func value(_ element: AXUIElement, attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.005)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    private static func focusedApplicationPID() -> pid_t? {
        guard let app = PublicInputAX.element(value(AXUIElementCreateSystemWide(), attribute: kAXFocusedApplicationAttribute)) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, pid > 0 else { return nil }
        return pid
    }
    private static func children(_ element: AXUIElement, attribute: String, maximum: Int) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(element, 0.005)
        var result: CFArray?
        guard AXUIElementCopyAttributeValues(element, attribute as CFString, 0, maximum + 1, &result) == .success,
              let values = result as? [AXUIElement], values.count <= maximum else { return nil }
        return values
    }

    private static func clipboardSnapshot() -> (count: Int, version: PublicFinderClipboardVersion?) {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard !types.contains("org.nspasteboard.ConcealedType"), !types.contains("org.nspasteboard.TransientType"),
              let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              pasteboard.changeCount == count else { return (pasteboard.changeCount, nil) }
        return (count, PublicFinderClipboardVersion(changeCount: count, files: urls.map { $0.standardizedFileURL.absoluteString }))
    }

    @MainActor private func scheduleCopyChecks(generation: UInt64) {
        cancelChecks()
        copyChecks = [0.04, 0.15, 0.4, 1.01].map { delay in
            let check = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lock.lock()
                    let active = self.state.enabled && self.state.generation == generation && self.state.copyDeadline != nil
                    self.lock.unlock()
                    guard active else { return }
                    let clipboard = Self.clipboardSnapshot()
                    self.lock.lock()
                    guard self.state.generation == generation, self.state.copyDeadline != nil else { self.lock.unlock(); return }
                    if let deadline = self.state.copyDeadline, ProcessInfo.processInfo.systemUptime > deadline {
                        self.state.copyDeadline = nil; self.state.policy.reset()
                    } else if self.state.policy.confirmCopy(current: clipboard.version, observedChangeCount: clipboard.count) { self.state.copyDeadline = nil }
                    self.lock.unlock()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: check)
            return check
        }
    }
    @MainActor private func cancelChecks() { copyChecks.forEach { $0.cancel() }; copyChecks.removeAll() }
    private func report(_ message: String) { DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.setStatus(message) } } }
    @MainActor private func setStatus(_ value: String?) {
        let value = value.map { L10n.string($0) }
        if status != value { status = value }
    }

    @MainActor func removeTap() {
        cancelChecks(); invalidate()
        if let token { GlobalEventTap.shared.unregister(token); self.token = nil }
        changes?.cancel(); changes = nil
        for (center, observer) in observers { center.removeObserver(observer) }; observers.removeAll()
        AccessibilityTrustMonitor.shared.unregister(name: "PublicFinderCutPaste")
        lock.lock(); state.enabled = false; lock.unlock()
        isActive = false
    }
}
#endif
