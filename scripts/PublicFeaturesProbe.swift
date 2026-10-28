import Foundation
@main struct PublicFeaturesProbe {
    static func main() {
        precondition(PublicFeatureAvailability.contains(.batteryWidget))
        precondition(PublicFeatureAvailability.contains(.snapZonesKeyboardShortcuts))
        precondition(PublicFeatureAvailability.contains(.focusProductiveAccess))
        precondition(PublicFeatureAvailability.contains(.basicStorageFeatures))
        precondition(PublicFeatureAvailability.contains(.audio8D))
        precondition(PublicFeatureAvailability.contains(.surroundSound))
        precondition(PublicFeatureAvailability.contains(.ocrFeature))
        precondition(PublicFeatureAvailability.contains(.clipboardPicker))
        precondition(PublicFeatureAvailability.contains(.mediaTools))
        precondition(PublicFeatureAvailability.contains(.storageWidgets))
        precondition(PublicFeatureAvailability.contains(.clipboardAutoClear))
        precondition(PublicFeatureAvailability.contains(.clipboardCleanURL))
        for unavailable in [AppFeature.appLock, .geminiLive, .liveSports, .financeWidget, .menuBarProfiles, .dockPresets, .continuityHandoff, .betaSoftwareUpdates] {
            precondition(!PublicFeatureAvailability.contains(unavailable), "Do not grant access to missing implementations: \(unavailable)")
        }
        precondition(!PublicFeatureAvailability.available.isEmpty)
        precondition(PublicFeatureAvailability.available.count < AppFeature.allCases.count)
        print("Public feature availability: implemented local features open; missing/private implementations stay unavailable")
    }
}
