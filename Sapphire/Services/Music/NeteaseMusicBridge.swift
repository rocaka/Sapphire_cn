import AppKit
import ApplicationServices

/// Controls only the installed NetEase process. Never sends global media keys.
@MainActor
final class NeteaseMusicBridge {
    static let shared = NeteaseMusicBridge()
    enum Action: Sendable { case play, pause, next, previous, like, shuffle, repeatOff, repeatTrack, repeatAll }
    struct State: Sendable {
        var liked: Bool?
        var shuffled: Bool?
        var repeatMode: String?
    }
    enum Failure: Error { case permission, notRunning, unavailable }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func perform(_ action: Action) async throws {
        guard isTrusted else { requestAccess(); throw Failure.permission }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: NeteaseMusicPolicy.bundleID).first else {
            throw Failure.notRunning
        }
        let pid = app.processIdentifier
        let succeeded = await Task.detached(priority: .userInitiated) {
            Self.press(action, pid: pid)
        }.value
        guard succeeded else { throw Failure.unavailable }
        try? await Task.sleep(for: .milliseconds(150))
    }

    func state() async -> State? {
        guard isTrusted, let app = NSRunningApplication.runningApplications(withBundleIdentifier: NeteaseMusicPolicy.bundleID).first else { return nil }
        let pid = app.processIdentifier
        return await Task.detached(priority: .utility) { Self.readState(pid: pid) }.value
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    nonisolated private static func title(_ element: AXUIElement) -> String {
        attribute(element, kAXTitleAttribute) as? String ?? ""
    }

    nonisolated private static func controlMenu(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar = attribute(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        let menuBar = unsafeBitCast(bar, to: AXUIElement.self)
        guard let control = children(menuBar).first(where: { ["控制", "Controls", "Control", "播放控制"].contains(title($0)) }) else { return nil }
        return children(control).first
    }

    nonisolated private static func find(_ menu: AXUIElement, titles: [String], depth: Int = 0) -> AXUIElement? {
        guard depth < 4 else { return nil }
        for item in children(menu) {
            if titles.contains(title(item)) { return item }
            if let found = find(item, titles: titles, depth: depth + 1) { return found }
        }
        return nil
    }

    nonisolated private static func checked(_ item: AXUIElement?) -> Bool? {
        guard let item else { return nil }
        // AppKit may return noValue for an unmarked item; unsupported is unknown.
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(item, kAXMenuItemMarkCharAttribute as CFString, &value)
        if result == .noValue { return false }
        guard result == .success, let mark = value as? String else { return nil }
        return !mark.isEmpty
    }

    nonisolated private static func press(_ action: Action, pid: pid_t) -> Bool {
        guard let menu = controlMenu(pid: pid) else { return false }
        let names: [String]
        switch action {
        case .play:
            if find(menu, titles: ["暂停", "Pause"]) != nil { return true }
            names = ["播放", "Play"]
        case .pause:
            if find(menu, titles: ["播放", "Play"]) != nil { return true }
            names = ["暂停", "Pause"]
        case .next: names = ["下一个", "下一首", "Next", "Next Track"]
        case .previous: names = ["上一个", "上一首", "Previous", "Previous Track"]
        case .like: names = ["喜欢歌曲", "取消喜欢", "取消喜欢歌曲", "喜欢", "Like Song", "Unlike Song"]
        case .shuffle: names = ["随机播放", "Shuffle"]
        case .repeatOff: names = ["关", "关闭", "Off"]
        case .repeatTrack: names = ["单曲", "One", "Repeat One"]
        case .repeatAll: names = ["全部", "All", "Repeat All"]
        }
        let targetMenu: AXUIElement
        switch action {
        case .repeatOff, .repeatTrack, .repeatAll:
            guard let repeatItem = find(menu, titles: ["循环播放", "Repeat"]), let submenu = children(repeatItem).first else { return false }
            targetMenu = submenu
        default: targetMenu = menu
        }
        guard let item = find(targetMenu, titles: names), attribute(item, kAXEnabledAttribute) as? Bool == true else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    nonisolated private static func readState(pid: pid_t) -> State? {
        guard let menu = controlMenu(pid: pid) else { return nil }
        var state = State()
        if find(menu, titles: ["取消喜欢", "取消喜欢歌曲", "Unlike Song"]) != nil {
            state.liked = true
        } else {
            state.liked = checked(find(menu, titles: ["喜欢歌曲", "喜欢", "Like Song"]))
        }
        state.shuffled = checked(find(menu, titles: ["随机播放", "Shuffle"]))
        for (names, mode) in [(["关", "关闭", "Off"], "off"), (["单曲", "One", "Repeat One"], "track"), (["全部", "All", "Repeat All"], "context")] {
            if checked(find(menu, titles: names)) == true { state.repeatMode = mode }
        }
        return state
    }
}
