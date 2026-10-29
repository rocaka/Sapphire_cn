// Public fork capabilities: no subscription, account or fabricated entitlement.
#if !SAPPHIRE_FULL_BUILD
import Foundation

public enum AppFeature: String, Codable, CaseIterable {
    case clipboardAutoClear, clipboardCleanURL
    case unlimitedLyricsFetch, translation, geminiLive, advancedFileConversion,
         priorityAutomation, betaSoftwareUpdates, circleToSearch, liveSports,
         financeWidget, sportsWidget, financeLiveActivity, prioritizedFeedback,
         appLock, focusProductiveAccess,
         menuBarProfiles, androidContinuitySyncMedia, androidContinuityWidgets,
         androidContinuityPhotoDisk, mediaTools, basicMouseSettings,
         dockPresets,
         continuityUniversalKeyboard, continuityEarbudHandoff,
         continuityHandoff, continuityDocumentScanning,
         continuityCameraAndMic, continuityMacTabsOnPhone,
         androidNotificationsOnMac, continuityCloudflareRelay, windowsPreview, dockPreview, allMouseSettings,
         surroundSound, snapZonesKeyboardShortcuts, emojiSuggestAsYouType,
         basicStorageFeatures, clipboardPicker, clipboardAdvancedTools, dmgInstaller,
         macScreenMirroringOnAndroid, macScreenExtensionOnMac, androidInstantHotspot,
         androidRemoteConnection, advancedStorageFeatures, batteryWidget, audio8D,
         storageWidgets, ocrFeature
}

enum PublicFeatureAvailability {
    static let available: Set<AppFeature> = [
        .unlimitedLyricsFetch, .translation, .snapZonesKeyboardShortcuts,
        .batteryWidget, .basicStorageFeatures,
        .audio8D, .surroundSound, .ocrFeature, .clipboardPicker, .clipboardAutoClear, .clipboardCleanURL, .mediaTools, .storageWidgets
    ]

    static func contains(_ feature: AppFeature) -> Bool { available.contains(feature) }
}
#endif
