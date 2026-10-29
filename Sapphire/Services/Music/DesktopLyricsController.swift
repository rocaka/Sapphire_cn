import AppKit
import Combine
import SwiftUI

@MainActor
final class DesktopLyricsController {
    static let shared = DesktopLyricsController()

    private struct Configuration: Equatable {
        let appearance: DesktopLyricsAppearance
        let displayTarget: NotchDisplayTarget
        let displayVisibility: [String: Bool]
        let hideFromScreenSharing: Bool
        let hideLyricsInFullScreen: Bool
        let displayFullScreenBehavior: [String: FullScreenBehavior]

        init(_ settings: Settings) {
            appearance = DesktopLyricsAppearancePolicy.resolve(settings.desktopLyricsAppearance)
            displayTarget = settings.notchDisplayTarget
            displayVisibility = settings.perDisplayShowNotch
            hideFromScreenSharing = settings.hideFromScreenSharing
            hideLyricsInFullScreen = settings.hideLyricsInFullScreen
            displayFullScreenBehavior = settings.perDisplayFullScreenBehavior
        }
    }

    private struct Playback: Equatable {
        var text: String
        var translation: String
        var isPlaying: Bool
        var source: String?
        var title: String?

        @MainActor init(_ manager: MusicManager) {
            text = manager.currentLyric?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            translation = manager.currentLyric?.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            isPlaying = manager.isPlaying
            source = manager.currentSourceKey ?? manager.lastKnownBundleID
            title = manager.title
        }

        var hasTrack: Bool { title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    private struct Anchor {
        let screen: NSScreen
        let frame: CGRect
        let expanded: Bool
        let moving: Bool
        let fullScreenHidden: Bool
    }

    private final class StageWatch {
        weak var stage: NotchStageView?
        let token = NSObject()
        init(_ stage: NotchStageView) { self.stage = stage }
    }

    private final class LyricsPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private struct RenderState: Equatable {
        let text: String
        let translation: String?
        let appearance: DesktopLyricsAppearance
    }

    @MainActor private final class PanelEntry {
        let panel: LyricsPanel
        let hosting: NSHostingView<DesktopLyricsOverlayView>
        var state: RenderState

        init(frame: CGRect, state: RenderState) {
            self.state = state
            panel = LyricsPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isMovable = false
            panel.isMovableByWindowBackground = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.animationBehavior = .none
            panel.title = L10n.string("Desktop Lyrics")
            hosting = NSHostingView(rootView: DesktopLyricsOverlayView(text: state.text, translation: state.translation, appearance: state.appearance))
            hosting.sizingOptions = []
            hosting.autoresizingMask = [.width, .height]
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            panel.contentView = hosting
        }
    }

    private var configuration: Configuration?
    private var configurationSubscription: AnyCancellable?
    private var runtimeSubscriptions = Set<AnyCancellable>()
    private var playback: Playback?
    private var stages: [ObjectIdentifier: StageWatch] = [:]
    private var panels: [CGDirectDisplayID: PanelEntry] = [:]
    private var lyricsAllowed = true
    private var fullScreenDisplays = Set<CGDirectDisplayID>()
    private var locked = false
    private var systemSleeping = false
    private var displaysSleeping = false
    private var sessionActive = true
    private var demandActive = false
    private var refreshScheduled = false
    private var generation: UInt64 = 0

    private init() {}

    func start() {
        guard configurationSubscription == nil else { return }
        locked = (NSApp.delegate as? AppDelegate)?.isScreenLocked ?? false
        configurationSubscription = SettingsModel.shared.changes(of: Configuration.init)
            .prepend(Configuration(SettingsModel.shared.current))
            .removeDuplicates()
            .sink { [weak self] configuration in self?.configure(configuration) }
    }

    func stop() {
        configurationSubscription?.cancel()
        configurationSubscription = nil
        configuration = nil
        deactivateRuntime()
    }

    private func configure(_ next: Configuration) {
        configuration = next
        guard next.appearance.enabled else { deactivateRuntime(); return }
        if runtimeSubscriptions.isEmpty { installRuntimeObservers() }
        scheduleRefresh()
    }

    private func installRuntimeObservers() {
        locked = (NSApp.delegate as? AppDelegate)?.isScreenLocked ?? locked
        lyricsAllowed = ActiveAppMonitor.shared.isLyricsAllowedForActiveApp
        fullScreenDisplays = ActiveAppMonitor.shared.fullScreenDisplayIDs
        observationPublisher { MainActor.assumeIsolated { Playback(MusicManager.shared) } }
            .removeDuplicates()
            .sink { [weak self] playback in
                self?.playback = playback
                self?.scheduleRefresh()
            }.store(in: &runtimeSubscriptions)
        ActiveAppMonitor.shared.$fullScreenDisplayIDs
            .removeDuplicates()
            .sink { [weak self] displays in
                self?.fullScreenDisplays = displays
                self?.scheduleRefresh()
            }.store(in: &runtimeSubscriptions)
        ActiveAppMonitor.shared.$isLyricsAllowedForActiveApp
            .removeDuplicates()
            .sink { [weak self] allowed in
                self?.lyricsAllowed = allowed
                if !allowed { self?.suspendDisplay() }
                self?.scheduleRefresh()
            }.store(in: &runtimeSubscriptions)

        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &runtimeSubscriptions)
        // New notch hosts are created asynchronously. Their normal AppKit update
        // notification lets us attach once available, without a polling timer.
        for name in [NSWindow.didUpdateNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
            center.publisher(for: name)
                .filter { $0.object is DynamicFocusWindow }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &runtimeSubscriptions)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.systemSleeping = true; self?.suspendDisplay() }.store(in: &runtimeSubscriptions)
        workspace.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.systemSleeping = false; self?.scheduleRefresh() }.store(in: &runtimeSubscriptions)
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.displaysSleeping = true; self?.suspendDisplay() }.store(in: &runtimeSubscriptions)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.displaysSleeping = false; self?.scheduleRefresh() }.store(in: &runtimeSubscriptions)
        workspace.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sessionActive = false; self?.suspendDisplay() }.store(in: &runtimeSubscriptions)
        workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sessionActive = true; self?.scheduleRefresh() }.store(in: &runtimeSubscriptions)
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &runtimeSubscriptions)

        let distributed = DistributedNotificationCenter.default()
        distributed.publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.locked = true; self?.suspendDisplay() }.store(in: &runtimeSubscriptions)
        distributed.publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.locked = false; self?.scheduleRefresh() }.store(in: &runtimeSubscriptions)
    }

    private func deactivateRuntime() {
        generation &+= 1
        refreshScheduled = false
        runtimeSubscriptions.removeAll()
        playback = nil
        systemSleeping = false
        displaysSleeping = false
        sessionActive = true
        setDemand(false)
        for watch in stages.values { watch.stage?.engine.removeObserver(watch.token) }
        stages.removeAll()
        for entry in panels.values { entry.panel.orderOut(nil); entry.panel.close() }
        panels.removeAll()
    }

    private func suspendDisplay() {
        setDemand(false)
        for entry in panels.values { entry.panel.orderOut(nil) }
    }

    private func setDemand(_ active: Bool) {
        guard demandActive != active else { return }
        demandActive = active
        MusicManager.shared.setDesktopLyricsActive(active)
    }

    private func scheduleRefresh() {
        guard configuration?.appearance.enabled == true, !refreshScheduled else { return }
        refreshScheduled = true
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func refresh() {
        guard let configuration, configuration.appearance.enabled else { return }
        let appearance = configuration.appearance
        let settings = SettingsModel.shared.current
        let targets = NotchScreens.screens(for: settings)
        let windows = NSApp.windows.compactMap { $0 as? DynamicFocusWindow }
        var anchors: [CGDirectDisplayID: Anchor] = [:]
        var observedStages: [ObjectIdentifier: NotchStageView] = [:]
        for screen in targets {
            guard CGDisplayIsAsleep(screen.displayID) == 0 else { continue }
            guard let window = windows.first(where: { $0.displayID == screen.displayID && !$0.isDisplayDetached && !$0.isNotchHidden && $0.isVisible }),
                  let stage = findStage(in: window.contentView) else { continue }
            observedStages[ObjectIdentifier(stage)] = stage
            let clip = stage.presentedClipFrame
            let config = ResolvedNotchConfiguration(from: settings, screen: screen)
            let bandOffset = max(0, config.topInset - config.topBuffer)
            let local = clip.offsetBy(dx: 0, dy: bandOffset)
            let anchor = window.convertToScreen(stage.convert(local, to: nil))
            guard clip.width > 0, clip.height > 0,
                  [anchor.minX, anchor.minY, anchor.width, anchor.height, anchor.maxX, anchor.maxY].allSatisfy(\.isFinite),
                  anchor.intersects(screen.frame) else { continue }
            anchors[screen.displayID] = Anchor(screen: screen, frame: anchor, expanded: stage.isExpandedContent,
                moving: stage.engine.activeTimeline != nil || stage.engine.currentFrame.isMoving,
                fullScreenHidden: fullScreenDisplays.contains(screen.displayID)
                    && settings.resolvedFullScreenBehavior(forDisplayID: screen.displayIdentifier).hideLyrics)
        }
        synchronizeStageWatches(observedStages)
        let primary = playback?.text ?? ""
        let translated = playback?.translation ?? ""
        let text = primary.isEmpty ? translated : primary
        let translation = appearance.showTranslation && !translated.isEmpty && translated != text ? translated : nil
        let hasLyric = playback?.hasTrack == true && !text.isEmpty
        var demand = false
        var visibleDisplays = Set<CGDirectDisplayID>()
        for (display, anchor) in anchors {
            let inputs = DesktopLyricsVisibilityPolicy.Inputs(enabled: appearance.enabled,
                locked: locked || !sessionActive, sleeping: systemSleeping || displaysSleeping,
                appAllowed: lyricsAllowed, hasAnchor: true, notchExpanded: anchor.expanded,
                isPlaying: playback?.isPlaying ?? false, hideWhenPaused: appearance.hideWhenPaused,
                hasCurrentLyric: hasLyric, fullScreenHidden: anchor.fullScreenHidden)
            demand = demand || DesktopLyricsVisibilityPolicy.needsLyrics(inputs)
            guard DesktopLyricsVisibilityPolicy.shouldDisplay(inputs), !anchor.moving else { continue }
            let state = RenderState(text: text, translation: translation, appearance: appearance)
            let frame = DesktopLyricsAppearancePolicy.frame(screenFrame: anchor.screen.frame, anchorFrame: anchor.frame,
                appearance: appearance, lineCount: translation == nil ? 1 : 2)
            guard frame.width > 0, frame.height > 0 else { continue }
            visibleDisplays.insert(display)
            let entry: PanelEntry
            if let existing = panels[display] {
                entry = existing
                if entry.state != state {
                    entry.state = state
                    entry.hosting.rootView = DesktopLyricsOverlayView(text: text, translation: translation, appearance: appearance)
                }
            } else {
                entry = PanelEntry(frame: frame, state: state)
                panels[display] = entry
            }
            entry.panel.sharingType = configuration.hideFromScreenSharing ? .none : .readOnly
            if entry.panel.frame != frame { entry.panel.setFrame(frame, display: true) }
            if !entry.panel.isVisible { entry.panel.orderFrontRegardless() }
        }
        setDemand(demand)
        for (display, entry) in panels where !visibleDisplays.contains(display) { entry.panel.orderOut(nil) }
        let targetIDs = Set(targets.map(\.displayID))
        for display in Array(panels.keys) where !targetIDs.contains(display) {
            panels[display]?.panel.close()
            panels[display] = nil
        }
    }

    private func synchronizeStageWatches(_ observed: [ObjectIdentifier: NotchStageView]) {
        for id in Array(stages.keys) where observed[id] == nil {
            if let watch = stages.removeValue(forKey: id) { watch.stage?.engine.removeObserver(watch.token) }
        }
        for (id, stage) in observed where stages[id] == nil {
            let watch = StageWatch(stage)
            stages[id] = watch
            stage.engine.addObserver(watch.token) { [weak self] _ in self?.scheduleRefresh() }
        }
    }

    private func findStage(in view: NSView?) -> NotchStageView? {
        guard let view else { return nil }
        if let stage = view as? NotchStageView { return stage }
        for child in view.subviews {
            if let stage = findStage(in: child) { return stage }
        }
        return nil
    }

}
