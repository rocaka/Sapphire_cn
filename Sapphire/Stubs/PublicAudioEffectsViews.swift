#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct EightDAudioView: View {
    let bundleID: String
    let appName: String
    @ObservedObject private var manager = MultiAudioManager.shared

    private func binding<Value>(_ key: WritableKeyPath<EightDAudioSettings, Value>) -> Binding<Value> {
        Binding(get: { manager.eightDAudioSettings(for: bundleID)[keyPath: key] }, set: { value in
            var settings = manager.eightDAudioSettings(for: bundleID)
            settings[keyPath: key] = value
            manager.setEightDAudioSettings(settings, for: bundleID)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(appName).font(.headline)
                Toggle("Enable 8D Audio", isOn: binding(\.enabled))
                control("Rotation Speed", \.rotationSpeed, 0.01...1)
                control("Depth", \.depth)
                control("Distance", \.distance)
                control("Elevation Motion", \.elevationMotion)
                control("Front/Back Motion", \.frontBackMotion)
                control("Room Size", \.roomSize)
                control("Room Spread", \.roomSpread)
                control("Bass Boost", \.bassBoost, 0...12)
                control("Intensity", \.intensity)
                control("Center Focus", \.centerFocus)
                Button("Reset") { manager.setEightDAudioSettings(EightDAudioSettings(), for: bundleID) }
            }.padding()
        }.frame(width: 400, height: 340)
    }

    private func control(_ title: String, _ key: WritableKeyPath<EightDAudioSettings, Double>, _ range: ClosedRange<Double> = 0...1) -> some View {
        HStack {
            Text(L10n.string(title)).font(.caption).frame(width: 125, alignment: .leading)
            Slider(value: binding(key), in: range)
            Text(binding(key).wrappedValue, format: .number.precision(.fractionLength(2)))
                .monospacedDigit().frame(width: 42)
        }
    }
}

struct SurroundAudioView: View {
    let bundleID: String
    let appName: String
    @ObservedObject private var manager = MultiAudioManager.shared

    private func binding<Value>(_ key: WritableKeyPath<SurroundAudioSettings, Value>) -> Binding<Value> {
        Binding(get: { manager.surroundAudioSettings(for: bundleID)[keyPath: key] }, set: { value in
            var settings = manager.surroundAudioSettings(for: bundleID)
            settings[keyPath: key] = value
            manager.setSurroundAudioSettings(settings, for: bundleID)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appName).font(.headline)
            Toggle("Enable Surround Audio", isOn: binding(\.enabled))
            control("Width", \.width, 1...2.5)
            control("Crossfeed", \.crossfeed, 0...0.5)
            control("Ambience", \.ambience)
            control("Depth", \.depth)
            control("Center Focus", \.centerFocus)
            Button("Reset") { manager.setSurroundAudioSettings(SurroundAudioSettings(), for: bundleID) }
        }.padding().frame(width: 400)
    }

    private func control(_ title: String, _ key: WritableKeyPath<SurroundAudioSettings, Double>, _ range: ClosedRange<Double> = 0...1) -> some View {
        HStack {
            Text(L10n.string(title)).font(.caption).frame(width: 125, alignment: .leading)
            Slider(value: binding(key), in: range)
            Text(binding(key).wrappedValue, format: .number.precision(.fractionLength(2)))
                .monospacedDigit().frame(width: 42)
        }
    }
}
#endif
