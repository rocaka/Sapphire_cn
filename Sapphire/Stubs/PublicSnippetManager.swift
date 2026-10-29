#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

/// Small AX reads, never a whole document or password value. Unsupported editors
/// are deliberately left alone rather than falling back to simulated deletion.
enum PublicInputAX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        let result = read(element, attribute)
        return result.error == .success ? result.value : nil
    }
    static func read(_ element: AXUIElement, _ attribute: String) -> (error: AXError, value: CFTypeRef?) {
        AXUIElementSetMessagingTimeout(element, 0.02)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error, value)
    }
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    static func focus(pid: pid_t) -> AXUIElement? {
        element(value(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute))
    }
    static func focusedApplicationPID() -> pid_t? {
        guard let app = element(value(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute)) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, pid > 0 else { return nil }
        return pid
    }
    static func isText(_ element: AXUIElement) -> Bool {
        guard let role = value(element, kAXRoleAttribute) as? String else { return false }
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
    }
    static func isSafeText(_ element: AXUIElement) -> Bool {
        guard isText(element) else { return false }
        let subrole = read(element, kAXSubroleAttribute)
        let protection = read(element, "AXProtectedContent")
        let optional: Set<AXError> = [.success, .noValue, .attributeUnsupported]
        guard optional.contains(subrole.error), optional.contains(protection.error),
              subrole.value as? String != kAXSecureTextFieldSubrole, protection.value as? Bool != true else { return false }
        return true
    }
    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let raw = value(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let box = unsafeBitCast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(box) == .cfRange, AXValueGetValue(box, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { return nil }
        return range
    }
    static func text(_ element: AXUIElement, range: CFRange) -> String? {
        var range = range
        guard let box = AXValueCreate(.cfRange, &range) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.02)
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, box, &value) == .success else { return nil }
        return value as? String
    }
    static func matches(_ match: PublicSnippetMatcher.Match, element: AXUIElement, range: CFRange) -> Bool {
        guard text(element, range: range) == match.typedSuffix else { return false }
        guard match.requiresWordBoundary, range.location > 0 else { return true }
        let count = min(4, range.location)
        return PublicSnippetMatcher.isWordBoundary(preceding: text(element, range: CFRange(location: range.location - count, length: count)))
    }
    static func setRange(_ range: CFRange, on element: AXUIElement) -> Bool {
        var range = range
        guard let box = AXValueCreate(.cfRange, &range) else { return false }
        AXUIElementSetMessagingTimeout(element, 0.02)
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, box) == .success
    }
    static func settable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        AXUIElementSetMessagingTimeout(element, 0.02)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }
    static func plainKeyboardLayout() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        let type = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
        // Input methods don't reliably expose their marked range through AX.
        // Skipping the entire input mode also covers in-progress composition.
        return type == kTISTypeKeyboardLayout
    }
}

@MainActor
final class SnippetManager: ObservableObject {
    static let shared = SnippetManager()
    @Published private(set) var status: String?
    @Published private(set) var isActive = false
    private var changes: AnyCancellable?
    private var tokens: [NSEvent.EventType: UUID] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var inputObserver: NSObjectProtocol?
    private var matcher = PublicSnippetMatcher()
    private var focus: AXUIElement?
    private var pending: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var suspended = false

    private struct Configuration: Equatable {
        let enabled: Bool
        let afterSpace: Bool
        let snippets: [SnippetEntry]
        let ignored: Set<String>
        init(_ settings: Settings) {
            enabled = settings.snippetsEnabled
            afterSpace = settings.snippetsExpandAfterSpace
            snippets = settings.snippetsList
            ignored = Set(settings.clipboardIgnoredAppBundleIDs.map { $0.lowercased() })
        }
    }
    private var configuration: Configuration?
    private init() {}

    func start() {
        guard changes == nil else { return }
        AccessibilityTrustMonitor.shared.register(name: "PublicSnippets", owner: self,
            teardown: { $0.resetInput(); $0.configure() }, reinstall: { $0.configure() })
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { $0.resetInput() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { $0.suspended = true; $0.configure() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.suspended = false; $0.configure() }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { $0.removeHandler() }
        inputObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configure() }
        }
        changes = SettingsModel.shared.changes(of: Configuration.init)
            .prepend(Configuration(SettingsModel.shared.current))
            .sink { [weak self] configuration in
                guard let self else { return }
                self.configuration = configuration
                self.matcher.configure(configuration.snippets.filter(\.isEnabled).map { .init(trigger: $0.trigger, replacement: $0.replacement) })
                self.configure()
            }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping (SnippetManager) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }))
    }

    private func configure() {
        resetInput()
        let enabled = configuration?.enabled == true && !matcher.rules.isEmpty && !suspended
        let trusted = AccessibilityTrustMonitor.isCurrentlyTrusted()
        let layout = PublicInputAX.plainKeyboardLayout()
        let armed = enabled && trusted && layout
        EventMonitorHub.shared.setRegistered(armed, tokens: &tokens,
            for: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in self?.receive(event) }
        isActive = armed
        if configuration?.enabled == true && matcher.rules.isEmpty { setStatus("Add an enabled text snippet with a trigger of at most 128 characters.") }
        else if !enabled { setStatus(nil) }
        else if !trusted { setStatus("Text snippets need Accessibility access. Enable Sapphire in System Settings.") }
        else if !layout { setStatus("Text snippets pause while an input method is selected to protect composing text.") }
        else { setStatus(nil) }
    }

    private func resetInput() {
        generation &+= 1
        pending?.cancel(); pending = nil
        matcher.reset(); focus = nil
    }

    private func receive(_ event: NSEvent) {
        pending?.cancel(); pending = nil
        guard event.type == .keyDown, let configuration, configuration.enabled,
              !IsSecureEventInputEnabled(), PublicInputAX.plainKeyboardLayout(),
              AccessibilityTrustMonitor.isCurrentlyTrusted(),
              let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !bundleID.hasPrefix((Bundle.main.bundleIdentifier ?? "com.rocaka.sapphirecn") + "."),
              !configuration.ignored.contains(bundleID.lowercased()),
              event.cgEvent.map({ $0.getIntegerValueField(.eventTargetUnixProcessID) <= 0 || $0.getIntegerValueField(.eventTargetUnixProcessID) == Int64(app.processIdentifier) }) ?? true,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !event.isARepeat else { resetInput(); return }
        guard let currentFocus = PublicInputAX.focus(pid: app.processIdentifier), PublicInputAX.isSafeText(currentFocus) else { resetInput(); return }
        if let focus, !CFEqual(focus, currentFocus) { resetInput() }
        focus = currentFocus
        if event.keyCode == 51 { matcher.backspace(); return }
        guard let text = event.characters, !text.isEmpty,
              ![36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(Int(event.keyCode)) else { resetInput(); return }
        guard let match = matcher.feed(text, source: "\(app.processIdentifier)", afterDelimiter: configuration.afterSpace) else { return }
        let token = generation
        let pid = app.processIdentifier
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            guard let self, !Task.isCancelled, generation == token else { return }
            pending = nil
            expand(match, target: currentFocus, pid: pid, token: token)
        }
    }

    private func expand(_ match: PublicSnippetMatcher.Match, target: AXUIElement, pid: pid_t, token: UInt64) {
        guard generation == token, configuration?.enabled == true, !suspended,
              AccessibilityTrustMonitor.isCurrentlyTrusted(), !IsSecureEventInputEnabled(), PublicInputAX.plainKeyboardLayout(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              PublicInputAX.focusedApplicationPID() == pid,
              let current = PublicInputAX.focus(pid: pid), CFEqual(current, target), PublicInputAX.isSafeText(current),
              let insertion = PublicInputAX.selectedRange(current), insertion.length == 0,
              insertion.location >= match.typedSuffix.utf16.count else { return }
        let range = CFRange(location: insertion.location - match.typedSuffix.utf16.count, length: match.typedSuffix.utf16.count)
        guard PublicInputAX.matches(match, element: current, range: range) else { return }
        guard PublicInputAX.settable(kAXSelectedTextRangeAttribute, on: current), PublicInputAX.settable(kAXSelectedTextAttribute, on: current) else {
            setStatus("This app does not support safe text snippet replacement through Accessibility."); return
        }
        let rendered: String
        do { rendered = try PublicSnippetTemplate.render(match.template, now: Date(), clipboard: readClipboard) }
        catch { setStatus("The snippet was left unchanged because its clipboard content is private, unavailable or too large."); return }
        // Verify again after template rendering, which can contact the pasteboard.
        guard generation == token, !IsSecureEventInputEnabled(), PublicInputAX.plainKeyboardLayout(), AccessibilityTrustMonitor.isCurrentlyTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              PublicInputAX.focusedApplicationPID() == pid,
              let latestFocus = PublicInputAX.focus(pid: pid), CFEqual(latestFocus, current),
              PublicInputAX.isSafeText(current),
              let latest = PublicInputAX.selectedRange(current), latest.location == insertion.location, latest.length == 0,
              PublicInputAX.matches(match, element: current, range: range) else { return }
        guard PublicInputAX.setRange(range, on: current) else { setStatus("This app did not allow the snippet selection to be changed."); return }
        // Setting a selection is a separate cross-process request. The editor
        // or user may have moved it before replying; never edit that new range.
        guard !IsSecureEventInputEnabled(), PublicInputAX.plainKeyboardLayout(), AccessibilityTrustMonitor.isCurrentlyTrusted(), PublicInputAX.isSafeText(current),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              PublicInputAX.focusedApplicationPID() == pid,
              let selectedFocus = PublicInputAX.focus(pid: pid), CFEqual(selectedFocus, current),
              let selected = PublicInputAX.selectedRange(current), selected.location == range.location, selected.length == range.length,
              PublicInputAX.matches(match, element: current, range: range) else { return }
        let result = AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, rendered as CFString)
        if result == .success {
            if PublicInputAX.focusedApplicationPID() == pid, let latestFocus = PublicInputAX.focus(pid: pid), CFEqual(latestFocus, current),
               let selected = PublicInputAX.selectedRange(current), selected.location == range.location, selected.length == rendered.utf16.count {
                _ = PublicInputAX.setRange(CFRange(location: range.location + rendered.utf16.count, length: 0), on: current)
            }
            setStatus(nil)
        } else {
            // Do not retry edits: cannotComplete may mean the editor already applied it.
            if PublicInputAX.focusedApplicationPID() == pid, let latestFocus = PublicInputAX.focus(pid: pid), CFEqual(latestFocus, current),
               let selected = PublicInputAX.selectedRange(current), selected.location == range.location, selected.length == range.length,
               PublicInputAX.text(current, range: range) == match.typedSuffix { _ = PublicInputAX.setRange(insertion, on: current) }
            setStatus("This app did not confirm the snippet replacement. No additional edit was attempted.")
        }
    }

    private func readClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let revision = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard PublicSnippetTemplate.permitsClipboardTypes(types) else { return nil }
        if let source = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source")),
           configuration?.ignored.contains(source.lowercased()) == true { return nil }
        guard let value = pasteboard.string(forType: .string), value.utf16.count <= 32_768,
              pasteboard.changeCount == revision else { return nil }
        return value
    }

    private func setStatus(_ value: String?) {
        let value = value.map { L10n.string($0) }
        if status != value { status = value }
    }

    func removeHandler() {
        resetInput()
        EventMonitorHub.shared.unregister(tokens: tokens); tokens.removeAll()
        changes?.cancel(); changes = nil
        for (center, observer) in observers { center.removeObserver(observer) }; observers.removeAll()
        if let inputObserver { DistributedNotificationCenter.default().removeObserver(inputObserver); self.inputObserver = nil }
        AccessibilityTrustMonitor.shared.unregister(name: "PublicSnippets")
        isActive = false
    }
}
#endif
