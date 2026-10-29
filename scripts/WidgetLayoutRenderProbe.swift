import AppKit
import SwiftUI

// Isolate the production layout/views from live services and user settings.
enum WidgetType { case music, weather, calendar, shortcuts, sports, finance, shopify, notes, clipboard, mirror, battery, timer, agent, focusSession, storage, dev }
struct Settings {}
enum CursorPosition { static func targetNotchScreen() -> NSScreen? { nil } }
enum NotchScreens { static func screens(for settings: Settings, among screens: [NSScreen]) -> [NSScreen] { screens } }
enum NotchWidgetMode { case weatherPlayer }
private struct NavigationKey: EnvironmentKey { static var defaultValue: Binding<[NotchWidgetMode]> { .constant([]) } }
extension EnvironmentValues {
    var navigationStack: Binding<[NotchWidgetMode]> {
        get { self[NavigationKey.self] }
        set { self[NavigationKey.self] = newValue }
    }
}
final class WeatherViewModel: ObservableObject {
    static let shared = WeatherViewModel()
    var iconName = "cloud"
    var temperature = "—°"
    var locationName = "Unavailable"
    var conditionDescription = "Grant Location access in Sapphire's Permissions settings to show weather."
    var windInfo = "— mph"
    var precipChance = "—%"
    var humidity = "—%"
}

@main struct WidgetLayoutRenderProbe {
    @MainActor static func main() throws {
        let destination = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) : nil
        if let destination { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }

        @MainActor func render<Content: View>(_ name: String, _ content: Content) throws -> CGSize {
            let host = NSHostingView(rootView: content.padding(12).background(.black).environment(\.colorScheme, .dark))
            let fitted = host.fittingSize
            host.frame = CGRect(origin: .zero, size: fitted)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("SwiftUI failed to render \(name)") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let size = CGSize(width: fitted.width - 24, height: fitted.height - 24)
            print("\(name): \(size.width) × \(size.height) pt")
            if let destination, let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: destination.appendingPathComponent(name + ".png"))
            }
            return size
        }

        let weather = try render("weather-permission", WeatherWidgetView())
        precondition(abs(weather.width - 210) <= 1, "A long permission message must fit the weather widget: \(weather)")
        WeatherViewModel.shared.temperature = "26°"
        WeatherViewModel.shared.locationName = "北京市海淀区很长的位置名称"
        WeatherViewModel.shared.conditionDescription = "晴间多云，东北风，超长中文天气说明"
        let chineseWeather = try render("weather-chinese", WeatherWidgetView())
        precondition(abs(chineseWeather.width - 210) <= 1)

        let normal = try render("row-normal", NotchWidgetRow(maximumWidth: 900) {
            HStack(spacing: 20) {
                Color.orange.frame(width: 280, height: 100)
                WeatherWidgetView()
                Color.blue.frame(width: 180, height: 100)
            }
        })
        precondition(abs(normal.width - 710) <= 1, "A fitting row must keep its normal width: \(normal)")
        for screenWidth: CGFloat in [600, 1280, 1512, 2560] {
            let maximum = WidgetLayoutPolicy.maximumBarWidth(notchDisplayWidth: screenWidth)
            let size = try render("row-overflow-\(Int(screenWidth))", NotchWidgetRow(maximumWidth: maximum) {
                HStack(spacing: 20) {
                    ForEach(0..<16) { index in
                        Text("组件 \(index + 1)").frame(width: 210, height: 100).background(.gray.opacity(0.2))
                    }
                }
            })
            precondition(size.width <= maximum + 1 && size.height >= 100, "Overflow must remain on screen and retain its height: \(size)")
        }
        for (name, message) in [
            ("notice-chinese", "当前版本需要辅助功能权限。如已开启，请从“应用程序”重新打开 Sapphire。"),
            ("notice-long", String(repeating: "NetEase is not responding. Please try again. ", count: 8))
        ] {
            let notice = try render(name, MusicPlayerNotice(message: message))
            precondition(abs(notice.width - 400) <= 1, "An error must wrap inside the player: \(notice)")
            if name == "notice-long" { precondition(notice.height > 14, "The notice must retain wrapped text") }
        }
        precondition(WidgetLayoutPolicy.gapWidth(showDividers: false) == 20)
        precondition(WidgetLayoutPolicy.gapWidth(showDividers: true) == 41)
        precondition(WidgetLayoutPolicy.totalWidth(for: [.weather, .calendar], showDividers: true) == 431)
        precondition(WidgetLayoutPolicy.fittingWidgets(from: [.weather, .calendar], availableWidth: 420, showDividers: true) == [.weather])
        precondition(WidgetLayoutPolicy.fittingWidgets(from: [.weather, .calendar], availableWidth: 431, showDividers: true) == [.weather, .calendar])
        precondition(WidgetLayoutPolicy.maximumBarWidth(notchDisplayWidth: 1512, horizontalPadding: 70) == 1394)
        let padded = try render("row-overflow-padded", NotchWidgetRow(maximumWidth: WidgetLayoutPolicy.maximumBarWidth(notchDisplayWidth: 1512, horizontalPadding: 70)) {
            HStack(spacing: 20) {
                ForEach(0..<16) { index in Text("组件 \(index + 1)").frame(width: 210, height: 100) }
            }
        }.padding(.horizontal, 35))
        precondition(padded.width <= 1512 - 48 + 1, "Outer content padding must be included in the screen bound")
        print("Widget layout: actual SwiftUI renders keep weather/messages bounded, normal row width unchanged, and overflow on screen")
    }
}
