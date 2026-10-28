#if !SAPPHIRE_FULL_BUILD
import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

private final class ClipboardPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPickerManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ClipboardPickerManager()
    private var panel: ClipboardPickerPanel?
    private var previousApp: NSRunningApplication?
    private var configuration: AnyCancellable?
    private var monitoring = false
    private var stopped = false
    private var sessionID = UUID()

    private struct Configuration: Equatable {
        let enabled: Bool
        let shortcut: KeyboardShortcut
        init(_ settings: Settings) {
            enabled = settings.clipboardPickerEnabled
            shortcut = settings.clipboardPickerShortcut
        }
    }

    private override init() {
        super.init()
        configuration = SettingsModel.shared.changes(of: Configuration.init)
            .prepend(Configuration(SettingsModel.shared.current))
            .sink { [weak self] _ in self?.registerShortcut() }
    }

    private func registerShortcut() {
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { [weak self] settings in
            guard self?.stopped == false, settings.clipboardPickerEnabled else { return [] }
            return [.init(identifier: ShortcutIdentifier.clipboardPicker, shortcut: settings.clipboardPickerShortcut,
                          perform: { [weak self] in self?.presentPicker() })]
        }, reportUnavailable: { _ in }), named: "community.clipboardPicker")
    }

    func presentPicker() {
        guard !stopped, SettingsModel.shared.current.clipboardPickerEnabled else { return }
        if panel?.isVisible == true { dismiss(); return }
        previousApp = NSWorkspace.shared.frontmostApplication
        sessionID = UUID()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ClipboardPickerContent(
            choose: { [weak self] item in self?.choose(item) },
            dismiss: { [weak self] in self?.dismiss() }
        ))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(mouse) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let x = min(max(mouse.x - panel.frame.width / 2, frame.minX), frame.maxX - panel.frame.width)
            let y = min(max(mouse.y - panel.frame.height - 12, frame.minY), frame.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        ClipboardManager.shared.beginHighPriorityMonitoring()
        monitoring = true
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> ClipboardPickerPanel {
        let panel = ClipboardPickerPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 410),
                                        styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L10n.string("Clipboard")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        return panel
    }

    private func choose(_ item: ClipboardItem) {
        let session = sessionID
        let target = previousApp
        let accepted = ClipboardManager.shared.copyItem(item) { [weak self] success in
            guard let self, session == self.sessionID, self.panel?.isVisible == true else { return }
            guard success else { NSSound.beep(); return }
            self.dismiss()
            guard AccessibilityPermission.isProcessTrusted, let target, !target.isTerminated else { return }
            target.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                // Never paste into an unrelated app if focus changed during the copy.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
                let source = CGEventSource(stateID: .hidSystemState)
                let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
                down?.flags = .maskCommand
                up?.flags = .maskCommand
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
            }
        }
        if !accepted { NSSound.beep() }
    }

    private func dismiss() {
        sessionID = UUID()
        panel?.orderOut(nil)
        if monitoring {
            monitoring = false
            ClipboardManager.shared.endHighPriorityMonitoring()
        }
    }

    func stopMonitoring() {
        stopped = true
        configuration?.cancel()
        configuration = nil
        registerShortcut()
        dismiss()
    }

    func windowWillClose(_ notification: Notification) { dismiss() }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
}

private struct ClipboardPickerContent: View {
    @ObservedObject private var clipboard = ClipboardManager.shared
    @StateObject private var search = ClipboardSearchModel()
    @State private var query = ""
    @State private var selection: String?
    @FocusState private var searchFocused: Bool
    let choose: (ClipboardItem) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search clipboard", text: $query)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
                .onSubmit { chooseSelected() }
            List(selection: $selection) {
                ForEach(search.results) { item in
                    Button { choose(item) } label: {
                        HStack {
                            Image(systemName: item.kind.spec.systemImage).frame(width: 22)
                            Text(item.preview).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            if item.isPinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).tag(item.id)
                        .contextMenu {
                            Button(item.isPinned ? "Unpin" : "Pin") { clipboard.setPinned(!item.isPinned, id: item.id) }
                            Button("Remove", role: .destructive) { clipboard.removeItem(id: item.id) }
                        }
                }
            }
            Text("Select an item to copy and paste. Without Accessibility access, use Command-V after copying.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12)
            .onAppear { updateSearch(); searchFocused = true }
            .onChange(of: query) { _, _ in updateSearch() }
            .onChange(of: clipboard.historyRevision) { _, _ in updateSearch() }
            .onChange(of: search.results) { _, items in
                if selection == nil || !items.contains(where: { $0.id == selection }) { selection = items.first?.id }
            }
            .onExitCommand(perform: dismiss)
            .onMoveCommand { direction in moveSelection(direction) }
    }

    private func updateSearch() {
        search.update(items: clipboard.recentItems, revision: clipboard.historyRevision, kinds: nil, query: query, debounce: true)
    }

    private func chooseSelected() {
        if let item = search.results.first(where: { $0.id == selection }) ?? search.results.first { choose(item) }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !search.results.isEmpty, direction == .up || direction == .down else { return }
        let current = search.results.firstIndex(where: { $0.id == selection }) ?? 0
        let next = min(max(current + (direction == .down ? 1 : -1), 0), search.results.count - 1)
        selection = search.results[next].id
    }
}
#endif
