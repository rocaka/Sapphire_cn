import Foundation

/// Looks up app-owned UI copy only. Never use this for filenames, notes, lyrics,
/// device names, command output, stored enum raw values, or protocol identifiers.
enum L10n {
    static func string(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    /// Keeps the original English label searchable in a Chinese interface.
    static func english(_ text: String) -> String {
        chineseToEnglish[text] ?? text
    }

    private static let chineseToEnglish: [String: String] = {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "zh-Hans.lproj"),
              let data = FileManager.default.contents(atPath: path),
              let dictionary = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String] else { return [:] }
        return Dictionary(dictionary.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }()
}
