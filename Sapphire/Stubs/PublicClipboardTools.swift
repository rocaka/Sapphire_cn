#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine

@MainActor
final class ClipboardAutoClearManager {
    static let shared = ClipboardAutoClearManager()
    private var subscription: PasteboardChangeMonitor.Token?
    private var changes: AnyCancellable?
    private var pending: DispatchWorkItem?
    private var sleepObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?

    private struct Configuration: Equatable {
        let enabled: Bool
        let interval: Double?
        let onSleep: Bool
        let onLock: Bool
        init(_ settings: Settings) {
            enabled = settings.clipboardAutoClearEnabled
            interval = PublicClipboardToolsPolicy.clearDelay(settings.clipboardAutoClearInterval)
            onSleep = settings.clipboardAutoClearOnSleep
            onLock = settings.clipboardAutoClearOnLock
        }
    }

    private init() {}

    func start() {
        guard changes == nil else { return }
        changes = SettingsModel.shared.changes(of: Configuration.init)
            .prepend(Configuration(SettingsModel.shared.current))
            .sink { [weak self] config in self?.configure(config) }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                let settings = SettingsModel.shared.current
                if settings.clipboardAutoClearEnabled && settings.clipboardAutoClearOnSleep { self?.clearNow() }
            }
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                let settings = SettingsModel.shared.current
                if settings.clipboardAutoClearEnabled && settings.clipboardAutoClearOnLock { self?.clearNow() }
            }
        }
    }

    private func configure(_ config: Configuration) {
        pending?.cancel()
        pending = nil
        if let subscription { PasteboardChangeMonitor.shared.unsubscribe(subscription); self.subscription = nil }
        guard config.enabled, config.interval != nil else { return }
        subscription = PasteboardChangeMonitor.shared.subscribe(interval: 1) { [weak self] count in self?.scheduleClear(changeCount: count) }
        scheduleClear(changeCount: NSPasteboard.general.changeCount)
    }

    private func scheduleClear(changeCount: Int) {
        pending?.cancel()
        pending = nil
        let settings = SettingsModel.shared.current
        guard NSPasteboard.general.types?.isEmpty == false, settings.clipboardAutoClearEnabled,
              let delay = PublicClipboardToolsPolicy.clearDelay(settings.clipboardAutoClearInterval) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard SettingsModel.shared.current.clipboardAutoClearEnabled,
                  PublicClipboardToolsPolicy.shouldClear(expectedChangeCount: changeCount, currentChangeCount: NSPasteboard.general.changeCount) else { return }
            self?.clearNow()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func clearNow() {
        pending?.cancel()
        pending = nil
        guard NSPasteboard.general.types?.isEmpty == false else { return }
        NSPasteboard.general.clearContents() // Saved history and pinned items remain untouched.
    }

    func stop() {
        changes?.cancel(); changes = nil
        pending?.cancel(); pending = nil
        if let subscription { PasteboardChangeMonitor.shared.unsubscribe(subscription); self.subscription = nil }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver); self.sleepObserver = nil }
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver); self.lockObserver = nil }
    }
}

@MainActor
final class CleanURLManager {
    static let shared = CleanURLManager()
    private var subscription: PasteboardChangeMonitor.Token?
    private var changes: AnyCancellable?

    private struct Configuration: Equatable {
        let enabled: Bool
        let automatic: Bool
        init(_ settings: Settings) {
            enabled = settings.clipboardCleanURLEnabled
            automatic = settings.clipboardCleanURLAutoClean
        }
    }

    private init() {}
    func start() {
        guard changes == nil else { return }
        changes = SettingsModel.shared.changes(of: Configuration.init)
            .prepend(Configuration(SettingsModel.shared.current))
            .sink { [weak self] config in
                guard let self else { return }
                self.stopPolling()
                if config.enabled && config.automatic {
                    self.subscription = PasteboardChangeMonitor.shared.subscribe(interval: 1, priority: 100) { [weak self] _ in self?.cleanClipboardLinkNow() }
                }
            }
    }

    func cleanClipboardLinkNow() {
        let settings = SettingsModel.shared.current
        guard settings.clipboardCleanURLEnabled else { return }
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        let types = pasteboard.types ?? []
        let allowed: Set<String> = [NSPasteboard.PasteboardType.string.rawValue, NSPasteboard.PasteboardType.URL.rawValue,
                                    "public.utf16-external-plain-text", "org.nspasteboard.source", "NSStringPboardType"]
        guard !types.isEmpty, types.allSatisfy({ allowed.contains($0.rawValue) }),
              let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL),
              let cleaned = PublicClipboardToolsPolicy.cleanURL(text, customParameters: settings.clipboardCleanURLCustomParams),
              pasteboard.changeCount == count else { return }
        pasteboard.clearContents()
        pasteboard.setString(cleaned, forType: .string)
        if types.contains(.URL) { pasteboard.setString(cleaned, forType: .URL) }
    }

    func stopPolling() {
        if let subscription { PasteboardChangeMonitor.shared.unsubscribe(subscription); self.subscription = nil }
    }
    func stopMonitoring() { stopPolling(); changes?.cancel(); changes = nil }
}
#endif
