import Foundation

@main
struct LocalizationProbe {
    static func main() {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let zh = Bundle(url: root.appendingPathComponent("zh-Hans.lproj"))!
        let en = Bundle(url: root.appendingPathComponent("en.lproj"))!
        precondition(L10n.string("General", bundle: zh) == "通用")
        precondition(L10n.string("Launch at Login", bundle: zh) == "登录时启动")
        precondition(L10n.string("General", bundle: en) == "General")
        precondition(L10n.string("A user's unrecognized filename.txt", bundle: zh) == "A user's unrecognized filename.txt")
        let format = L10n.string("No settings matched \"%@\".", bundle: zh)
        precondition(String(format: format, "中文测试") == "没有与“中文测试”匹配的设置。")
        print("Chinese/English bundle lookup, fallback and formatted interpolation passed")
    }
}
