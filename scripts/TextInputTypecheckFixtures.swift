// Type-check only. This file is never linked into the application or executed.
import AppKit
import ApplicationServices
import Combine

enum L10n { static func string(_ value: String, bundle: Bundle = .main) -> String { value } }

struct SnippetEntry: Equatable { var trigger: String; var replacement: String; var isEnabled: Bool }
struct Settings {
    var snippetsEnabled = false
    var snippetsExpandAfterSpace = true
    var snippetsList: [SnippetEntry] = []
    var clipboardIgnoredAppBundleIDs: [String] = []
    var clipboardFinderCutPasteEnabled = false
}
@MainActor final class SettingsModel {
    static let shared = SettingsModel()
    var current = Settings()
    func changes<T: Equatable>(of transform: @escaping (Settings) -> T) -> AnyPublisher<T, Never> { Empty().eraseToAnyPublisher() }
}
@MainActor final class AccessibilityTrustMonitor {
    static let shared = AccessibilityTrustMonitor()
    nonisolated static func isCurrentlyTrusted() -> Bool { false }
    nonisolated func register<Owner: AnyObject>(name: String, owner: Owner, teardown: @escaping @MainActor (Owner) -> Void, reinstall: @escaping @MainActor (Owner) -> Void) {}
    nonisolated func unregister(name: String) {}
}
enum EventTapDecision { case pass, swallow, replace(CGEvent) }
enum EventTapPriority { static let transform = 400 }
final class GlobalEventTap: @unchecked Sendable {
    static let shared = GlobalEventTap()
    struct Token {}
    func register(name: String, mask: CGEventMask, priority: Int, enabled: Bool = true, reset: (() -> Void)? = nil, body: @escaping (CGEventType, CGEvent) -> EventTapDecision) -> Token { Token() }
    func unregister(_ token: Token) {}
    func setEnabled(_ token: Token, _ enabled: Bool) {}
}
