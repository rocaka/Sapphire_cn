import Foundation
@main struct ClipboardToolsProbe {
    static func main() {
        precondition(PublicClipboardToolsPolicy.cleanURL("https://example.com/item?id=a%2Bb&UTM_Source=x#section") == "https://example.com/item?id=a%2Bb#section")
        precondition(PublicClipboardToolsPolicy.cleanURL("https://example.com/?utm_source=x&fbclid=y") == "https://example.com/")
        precondition(PublicClipboardToolsPolicy.cleanURL("https://example.com/?id=42&ref=share") == nil)
        precondition(PublicClipboardToolsPolicy.cleanURL("https://example.com/?id=42&ref=share", customParameters: ["ref"]) == "https://example.com/?id=42")
        precondition(PublicClipboardToolsPolicy.cleanURL("https://example.com/?sig=secret&utm_source=x") == nil)
        precondition(PublicClipboardToolsPolicy.cleanURL("https://example.com/?X-Amz-Signature=secret&utm_source=x") == nil)
        precondition(PublicClipboardToolsPolicy.cleanURL("https://user:secret@example.com/?utm_source=x") == nil)
        precondition(PublicClipboardToolsPolicy.cleanURL("file:///tmp/file?utm_source=x") == nil)
        precondition(PublicClipboardToolsPolicy.cleanURL("https://example.com/?utm_source=x\nAnother line") == nil)
        precondition(PublicClipboardToolsPolicy.clearDelay(.nan) == nil)
        precondition(PublicClipboardToolsPolicy.clearDelay(-1) == nil)
        precondition(PublicClipboardToolsPolicy.clearDelay(30) == 30)
        precondition(PublicClipboardToolsPolicy.clearDelay(.infinity) == nil)
        precondition(!PublicClipboardToolsPolicy.shouldClear(expectedChangeCount: 4, currentChangeCount: 5))
        precondition(PublicClipboardToolsPolicy.shouldClear(expectedChangeCount: 5, currentChangeCount: 5))
        print("Clipboard tools: URL encoding/signatures preserved, tracking removed, stale auto-clear requests rejected")
    }
}
