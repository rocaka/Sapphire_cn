#if !SAPPHIRE_FULL_BUILD
import Foundation

enum PublicClipboardToolsPolicy {
    static func clearDelay(_ seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 86_400)
    }

    static func shouldClear(expectedChangeCount: Int, currentChangeCount: Int) -> Bool {
        expectedChangeCount == currentChangeCount
    }

    /// Removes only query components; preserves the exact encoding of retained data.
    /// Signed URLs are left unchanged because modifying their query invalidates them.
    static func cleanURL(_ text: String, customParameters: [String] = []) -> String? {
        guard text.utf8.count <= 262_144,
              !text.contains(where: { $0.isNewline }),
              var url = URLComponents(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil,
              let query = url.percentEncodedQuery else { return nil }
        let parts = query.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        func name(_ part: String) -> String {
            let key = String(part.prefix { $0 != "=" })
            return (key.removingPercentEncoding ?? key).lowercased()
        }
        let signedKeys: Set<String> = ["sig", "signature", "x-amz-signature", "x-goog-signature", "awsaccesskeyid"]
        if parts.contains(where: { signedKeys.contains(name($0)) }) { return nil }
        let trackers: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid", "_hsenc", "_hsmi"]
        let custom = Set(customParameters.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let retained = parts.filter {
            let key = name($0)
            return !key.hasPrefix("utm_") && !trackers.contains(key) && !custom.contains(key)
        }
        guard retained.count != parts.count else { return nil }
        url.percentEncodedQuery = retained.isEmpty ? nil : retained.joined(separator: "&")
        return url.string
    }
}
#endif
