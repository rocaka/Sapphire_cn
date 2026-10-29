//
//  MusicSettingsTabs.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26

import AppKit
import MusicKit
import SwiftUI

enum MusicSettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case player = "Player"
    case features = "Features"
    case accounts = "Accounts"
    case lyrics = "Lyrics"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .player: return "play.rectangle"
        case .features: return "sparkles"
        case .accounts: return "person.crop.circle"
        case .lyrics: return "quote.bubble"
        }
    }
}

// MARK: - Player features (shared by Spotify and Apple Music)

struct MusicPlayerFeaturesCard: View {
    @EditingSettings var settings: SettingsEditingSession
    let isSpotifyAvailable: Bool

    enum Service {
        case spotify, appleMusic

        var title: String { self == .spotify ? "Spotify" : "Apple Music" }
        var color: Color { self == .spotify ? .green : .pink }
        var icon: String { self == .spotify ? "dot.radiowaves.left.and.right" : "music.note" }
    }

    var body: some View {
        SettingsCard(
            title: "Player Features",
            description: "Extras shown in the music player. Each one applies to every service that supports it."
        ) {
            if !isSpotifyAvailable {
                InfoContainer(
                    text: "Spotify extras need the Spotify Private API login in the Accounts tab. Apple Music extras work without it.",
                    iconName: "info.circle",
                    color: .blue
                )
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            row("Artist Profile",
                "Show the artist's picture next to their name. Spotify adds the verified check and monthly listeners; Apple Music adds genre, release year and your play count.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowArtistProfile)
            Divider().padding(.leading, 20)
            row("Popularity",
                "Show the track's popularity score. Apple Music scores come from stats.fm and need no login.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.showPopularityInMusicPlayer)
            Divider().padding(.leading, 20)
            row("Next Song",
                "Show the upcoming track from the queue under the now-playing title.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowNextSong)
            Divider().padding(.leading, 20)
            row("Next Song Album Art",
                "Show album art beside the upcoming track in the live activity.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowNextSongAlbumArt)
                .disabled(!settings.settings.spotifyShowNextSong)
            Divider().padding(.leading, 20)
            row("Suggested Songs",
                "Show song chips you can play from the music player: related tracks on Spotify, more by the artist on Apple Music.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowSuggestedSongs)
            Divider().padding(.leading, 20)
            row("Concert Tickets",
                "Show a compact tickets button when nearby concerts are available for the artist.",
                services: [.spotify],
                isOn: $settings.settings.spotifyShowConcertTickets)
            Divider().padding(.leading, 20)
            row("Account Badge",
                "Show the Premium / Free account badge next to the track title.",
                services: [.spotify],
                isOn: $settings.settings.spotifyShowAccountBadge)
        }
    }

    private func row(_ title: String, _ description: String, services: [Service], isOn: Binding<Bool>) -> some View {
        let available = services.contains(.appleMusic) || isSpotifyAvailable
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(services, id: \.title) { service in
                        StatusCapsuleLabel(title: service.title, color: service.color, icon: service.icon)
                    }
                }
            }
            Spacer(minLength: 8)
            SettingsSwitch(title: title, isOn: isOn)
        }
        .padding()
        .disabled(!available)
        .opacity(available ? 1 : 0.5)
    }
}

// MARK: - Apple Music account

struct AppleMusicAccountCard: View {
    private var musicKit: MusicKitAppleMusicManager { .shared }
    @State private var isRequesting = false

    private var account: AppleMusicAccountState { musicKit.account }

    var body: some View {
        SettingsCard(
            title: "Apple Music",
            description: "Sapphire uses MusicKit for Apple Music artwork, artist details, the queue and your library. No login is needed beyond Apple Music access."
        ) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon).foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                    if let detail = statusDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                actionButton
            }
            .padding()
        }
        .onAppear { musicKit.refreshAuthorizationStatus() }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch account.authorization {
        case .notDetermined:
            Button(isRequesting ? "Requesting…" : "Allow Access") {
                isRequesting = true
                Task {
                    await AppleMusicManager.shared.requestAuthorization()
                    isRequesting = false
                }
            }
            .disabled(isRequesting)
        case .denied, .restricted:
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                    NSWorkspace.shared.open(url)
                }
            }
        default:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch account.authorization {
        case .authorized: return account.canPlayCatalogContent ? "Connected · Apple Music subscription" : "Connected · no subscription"
        case .notDetermined: return "Not connected"
        case .denied: return "Access is off"
        case .restricted: return "Access is restricted"
        @unknown default: return "Unknown"
        }
    }

    private var statusDetail: String? {
        if let error = account.lastError { return error }
        switch account.authorization {
        case .authorized:
            return account.canPlayCatalogContent ? nil : "Library and Music.app playback work; catalog playback needs a subscription."
        case .notDetermined:
            return "Allow access to show artwork, artist profiles and Up Next for Apple Music."
        case .denied, .restricted:
            return "Turn on Sapphire in System Settings › Privacy & Security › Media & Apple Music."
        @unknown default:
            return nil
        }
    }

    private var statusIcon: String {
        switch account.authorization {
        case .authorized: return "checkmark.circle.fill"
        case .notDetermined: return "circle.dashed"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch account.authorization {
        case .authorized: return .green
        case .notDetermined: return .secondary
        default: return .orange
        }
    }
}

struct NeteaseMusicSettingsCard: View {
    @EditingSettings var settings: SettingsEditingSession
    @State private var trusted = false
    @State private var diagnostics: NeteaseMusicBridge.Diagnostics?
    @State private var checking = false
    @State private var showConnectionDetails = false

    var body: some View {
        SettingsCard(title: "NetEase Cloud Music", description: "NetEase integration uses the macOS player and native controls. No NetEase account login is stored in Sapphire.") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show NetEase playback controls", isOn: $settings.settings.neteaseShowPlayerControls)
                Text(L10n.string("Playback uses macOS media controls. Favorites, shuffle and repeat use NetEase's native menu and need Accessibility access."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.string("Manage your queue, playlists, search and account in the NetEase app. Sapphire controls its current playback."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(L10n.string(trusted ? "Accessibility access enabled" : "Accessibility access required"), systemImage: trusted ? "checkmark.circle" : "hand.raised")
                    Spacer()
                    Button(L10n.string("Open NetEase Cloud Music")) { DefaultMusicPlayer.neteaseMusic.open() }
                    Button(L10n.string("Accessibility Settings")) {
                        NeteaseMusicBridge.shared.requestAccess()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                HStack {
                    Button(L10n.string("Check NetEase Connection")) {
                        guard !checking else { return }
                        checking = true
                        Task { @MainActor in
                            let result = await NeteaseMusicBridge.shared.checkConnection()
                            diagnostics = result
                            trusted = result.processTrusted
                            showConnectionDetails = true
                            checking = false
                        }
                    }.disabled(checking)
                    if checking { ProgressView().controlSize(.small) }
                    if let diagnostics, diagnostics.lastFailure == nil, diagnostics.accessVerified == true {
                        Label(L10n.string("NetEase native controls are available."), systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !trusted {
                    Text(L10n.string("Authorize the running copy of Sapphire. If an older copy is listed, remove it, add this copy, then quit and reopen the app."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L10n.string("Show This Copy of Sapphire")) {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
                if let diagnostics {
                    DisclosureGroup(L10n.string("Connection Details"), isExpanded: $showConnectionDetails) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string(diagnostics.processTrusted
                                ? "macOS recognizes Accessibility access for this running copy."
                                : "macOS does not recognize Accessibility access for this running copy, even if an older entry is enabled."))
                            Text(diagnostics.runningAppPath).textSelection(.enabled)
                            if let revision = diagnostics.sourceRevision {
                                Text(L10n.string("Source revision") + ": " + String(revision.prefix(12)))
                                    .textSelection(.enabled)
                            }
                            if let stage = diagnostics.failureStage {
                                Text(stage).textSelection(.enabled)
                            }
                            if let code = diagnostics.axErrorCode {
                                Text("AX: \(code)").textSelection(.enabled)
                            }
                            if diagnostics.lastFailure == .notRunning {
                                Text(L10n.string("Open NetEase Cloud Music before using its controls."))
                            } else if diagnostics.lastFailure == .unavailable {
                                Text(L10n.string("The NetEase native control menu is unavailable in this client state."))
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding()
        }
        .onAppear { refreshPermissionState() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: AccessibilityTrustMonitor.trustDidChange)) { _ in
            refreshPermissionState()
        }
    }

    private func refreshPermissionState() {
        let snapshot = NeteaseMusicBridge.shared.diagnosticSnapshot()
        trusted = snapshot.processTrusted
        diagnostics = snapshot
    }
}
