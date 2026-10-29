import Foundation

/// Only an enabled trigger's bounded suffix lives in memory; no input history is
/// persisted, published, or included in diagnostics.
struct PublicSnippetRule: Equatable, Sendable {
    let trigger: String
    let replacement: String
}

struct PublicSnippetMatcher {
    struct Match: Equatable {
        let typedSuffix: String
        let template: String
        let requiresWordBoundary: Bool
        init(typedSuffix: String, template: String, requiresWordBoundary: Bool = false) {
            self.typedSuffix = typedSuffix; self.template = template; self.requiresWordBoundary = requiresWordBoundary
        }
    }
    private(set) var buffer = ""
    private var source: String?
    private(set) var rules: [PublicSnippetRule] = []
    private var maximumLength = 0

    mutating func configure(_ candidates: [PublicSnippetRule]) {
        var seen = Set<String>()
        rules = candidates.filter {
            !$0.trigger.isEmpty && $0.trigger.count <= 128 && $0.trigger.utf16.count <= 512
                && !Self.containsControl($0.trigger)
                && $0.replacement.utf16.count <= 32_768 && seen.insert($0.trigger).inserted
        }.sorted { $0.trigger.count > $1.trigger.count }
        maximumLength = min(514, (rules.map { $0.trigger.count }.max() ?? 0) + 2)
        reset()
    }

    mutating func reset() { buffer = ""; source = nil }
    mutating func backspace() { if !buffer.isEmpty { buffer.removeLast() } }

    mutating func feed(_ text: String, source nextSource: String, afterDelimiter: Bool) -> Match? {
        if source != nextSource { reset(); source = nextSource }
        guard !rules.isEmpty, !text.isEmpty, text.count <= 8,
              !Self.containsControl(text) else { reset(); return nil }
        buffer += text
        buffer = String(buffer.suffix(maximumLength))
        // A single pathological composed character must not defeat the bound.
        guard buffer.utf16.count <= 2_048 else { reset(); return nil }
        let delimiter = afterDelimiter ? buffer.last.map(String.init) ?? "" : ""
        if afterDelimiter {
            guard let last = buffer.last,
                  last.unicodeScalars.allSatisfy({ CharacterSet.whitespaces.contains($0) || CharacterSet.punctuationCharacters.contains($0) }) else { return nil }
        }
        let body = afterDelimiter ? String(buffer.dropLast()) : buffer
        for rule in rules where body.hasSuffix(rule.trigger) {
            let prefix = body.dropLast(rule.trigger.count)
            // Plain-word triggers start at a word boundary; punctuation-prefixed
            // triggers (such as ;sig) remain usable inside normal prose.
            if let first = rule.trigger.first, first.isLetter || first.isNumber,
               let previous = prefix.last, previous.isLetter || previous.isNumber || previous == "_" { continue }
            let suffix = String(body.suffix(rule.trigger.count)) + delimiter
            reset()
            return Match(typedSuffix: suffix, template: rule.replacement + delimiter,
                requiresWordBoundary: rule.trigger.first.map { $0.isLetter || $0.isNumber } ?? false)
        }
        return nil
    }

    private static func containsControl(_ text: String) -> Bool {
        // ZWJ / variation selectors are valid parts of Unicode triggers.
        text.unicodeScalars.contains { $0.value < 0x20 || (0x7f...0x9f).contains($0.value) || CharacterSet.newlines.contains($0) }
    }

    static func isWordBoundary(preceding: String?) -> Bool {
        guard let preceding else { return false }
        guard let scalar = preceding.unicodeScalars.last else { return true }
        return !CharacterSet.alphanumerics.contains(scalar) && !CharacterSet.nonBaseCharacters.contains(scalar) && scalar.value != 0x5f
    }
}

enum PublicSnippetTemplate {
    enum Failure: Error { case clipboardUnavailable, outputTooLarge }
    static func render(_ template: String, now: Date, clipboard: () -> String?) throws -> String {
        let expression = try! NSRegularExpression(pattern: #"\{\{(date(?::[^{}]{1,80})?|time|clipboard)\}\}"#)
        let source = template as NSString
        var output = ""
        var cursor = 0
        var clipboardValue: String?
        var readClipboard = false
        for match in expression.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = source.substring(with: match.range(at: 1))
            if token == "clipboard" {
                if !readClipboard { clipboardValue = clipboard(); readClipboard = true }
                guard let clipboardValue else { throw Failure.clipboardUnavailable }
                output += clipboardValue
            } else {
                let formatter = DateFormatter()
                formatter.locale = .current
                formatter.dateFormat = token == "time" ? "HH:mm" : (token == "date" ? "yyyy-MM-dd" : String(token.dropFirst(5)))
                output += formatter.string(from: now)
            }
            guard output.utf16.count <= 32_768 else { throw Failure.outputTooLarge }
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        guard output.utf16.count <= 32_768 else { throw Failure.outputTooLarge }
        return output
    }

    static func permitsClipboardTypes(_ types: Set<String>) -> Bool {
        let blocked = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        return types.contains("public.utf8-plain-text") && blocked.allSatisfy { !types.contains($0) }
    }
}

struct PublicFinderClipboardVersion: Equatable, Sendable {
    let changeCount: Int
    let files: [String]
    init?(changeCount: Int, files: [String]) {
        guard !files.isEmpty, files.count <= 512,
              files.allSatisfy({ URL(string: $0)?.isFileURL == true }) else { return nil }
        self.changeCount = changeCount
        self.files = files.sorted()
    }
}

struct PublicFinderCutPolicy {
    static func acceptsTarget(enabled: Bool, finderPID: Int32?, focusedPID: Int32?, eventTargetPID: Int64) -> Bool {
        guard enabled, let finderPID, finderPID > 0, focusedPID == finderPID else { return false }
        return eventTargetPID <= 0 || eventTargetPID == Int64(finderPID)
    }
    private(set) var version: PublicFinderClipboardVersion?
    private var awaiting: (changeCount: Int, files: [String])?
    mutating func beginCopy(changeCount: Int, files: [String]) {
        reset()
        guard let selection = PublicFinderClipboardVersion(changeCount: changeCount, files: files) else { return }
        awaiting = (changeCount, selection.files)
    }
    @discardableResult
    mutating func confirmCopy(current: PublicFinderClipboardVersion?, observedChangeCount: Int? = nil) -> Bool {
        guard let awaiting else { return false }
        let observed = observedChangeCount ?? current?.changeCount
        guard let observed, observed != awaiting.changeCount else { return false }
        guard let current, current.changeCount == observed, current.files == awaiting.files else { reset(); return false }
        self.awaiting = nil
        version = current
        return true
    }
    mutating func reset() { version = nil; awaiting = nil }
    mutating func consume(current: PublicFinderClipboardVersion?, finderActive: Bool) -> Bool {
        defer { reset() }
        return finderActive && version != nil && version == current
    }
}
