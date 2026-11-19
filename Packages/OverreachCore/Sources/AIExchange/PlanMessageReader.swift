import Foundation

/// Finds an `overreach.plan` message in pasted text or a file: a fenced code block, the whole text, or the JSON
/// object inside it. Tolerant of text around the JSON, strict about the format and version.
public enum PlanMessageReader {
    public enum Failure: Error, Hashable, Sendable {
        /// No JSON object in the text.
        case noJSON
        /// JSON, but another format (e.g. the context pack). `nil` = no `format` field.
        case notAPlan(format: String?)
        /// Made for a newer app.
        case newerVersion(Int)
        case unsupportedVersion(Int)
        /// A plan whose JSON could not be read, with where (English, e.g. "routines[0].exercises should be a list").
        case invalid(String)
    }

    public static func read(_ text: String) -> Result<PlanMessage, Failure> {
        var firstFailure: Failure?
        for candidate in candidates(in: text) {
            switch read(candidate: candidate) {
            case let .success(message):
                return .success(message)
            case let .failure(failure):
                // A plan that failed explains more than a block that was not a plan at all.
                if case .notAPlan = failure, firstFailure != nil { continue }
                if firstFailure == nil || isAboutAPlan(failure) && !isAboutAPlan(firstFailure) {
                    firstFailure = failure
                }
            }
        }
        return .failure(firstFailure ?? .noJSON)
    }

    public static func read(_ data: Data) -> Result<PlanMessage, Failure> {
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.noJSON) }
        return read(text)
    }

    // MARK: - Helpers

    private struct Envelope: Decodable {
        var format: String?
        var version: Int?
    }

    private static func isAboutAPlan(_ failure: Failure?) -> Bool {
        switch failure {
        case .newerVersion, .unsupportedVersion, .invalid: true
        default: false
        }
    }

    private static func read(candidate: String) -> Result<PlanMessage, Failure> {
        let data = Data(candidate.utf8)
        let decoder = JSONDecoder()
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            guard candidate.hasPrefix("{") else { return .failure(.noJSON) }
            return .failure(.invalid(JSONSyntax.describeProblem(in: candidate) ?? describe(error)))
        }
        guard envelope.format == PlanMessage.formatName else { return .failure(.notAPlan(format: envelope.format)) }
        let version = envelope.version ?? 0
        guard version <= PlanMessage.currentVersion else { return .failure(.newerVersion(version)) }
        guard version >= 1 else { return .failure(.unsupportedVersion(version)) }
        do {
            var message = try decoder.decode(PlanMessage.self, from: data)
            if let json = try? decoder.decode(JSONValue.self, from: data) {
                message.ignoredFields = ignoredFields(in: json)
            }
            return .success(message)
        } catch {
            return .failure(.invalid(describe(error)))
        }
    }

    /// Paths of the fields the format does not read, e.g. `routines[0].reps`.
    static func ignoredFields(in json: JSONValue) -> [String] {
        var found: [String] = []
        unknown(in: json, kind: "plan", path: "", found: &found)
        return found
    }

    private static let children: [String: (kind: String, isList: Bool)] = [
        "routines": ("routine", true), "exerciseSettings": ("exerciseSettings", true), "scheme": ("scheme", false),
    ]

    private static func unknown(in json: JSONValue, kind: String, path: String, found: inout [String]) {
        guard case let .object(fields) = json, let known = PlanMessage.fields[kind] else { return }
        for key in fields.keys.sorted() {
            let keyPath = path.isEmpty ? key : "\(path).\(key)"
            guard known.contains(key) else {
                found.append(keyPath)
                continue
            }
            guard let child = children[key], let value = fields[key] else { continue }
            if child.isList, case let .array(items) = value {
                for (index, item) in items.enumerated() {
                    unknown(in: item, kind: child.kind, path: "\(keyPath)[\(index)]", found: &found)
                }
            } else if !child.isList {
                unknown(in: value, kind: child.kind, path: keyPath, found: &found)
            }
        }
    }

    /// Code blocks first, then the whole text, then from the first `{` to the last `}`.
    static func candidates(in text: String) -> [String] {
        var found: [String] = []
        let parts = text.components(separatedBy: "```")
        for (index, part) in parts.enumerated() where index % 2 == 1 {
            var block = Substring(part)
            if let newline = block.firstIndex(of: "\n"), !block[..<newline].contains("{") {
                block = block[block.index(after: newline)...]  // language tag, e.g. "json"
            }
            found.append(block.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        found.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close {
            found.append(String(text[open...close]))
        }
        var seen = Set<String>()
        return found.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return "the JSON could not be read" }
        switch error {
        case let .typeMismatch(type, context):
            return "\(path(context.codingPath)) should be \(typeName(type))"
        case let .valueNotFound(type, context):
            return "\(path(context.codingPath)) is empty but should be \(typeName(type))"
        case let .keyNotFound(key, context):
            return "\(path(context.codingPath + [key])) is missing"
        case let .dataCorrupted(context):
            return context.codingPath.isEmpty ? "the JSON is not valid" : "\(path(context.codingPath)) is not valid"
        @unknown default:
            return "the JSON could not be read"
        }
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        let text = keys.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
        return text.hasPrefix(".") ? String(text.dropFirst()) : (text.isEmpty ? "the JSON" : text)
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a text"
        case is Int.Type: "a whole number"
        case is Double.Type: "a number"
        case is Bool.Type: "true or false"
        default: String(describing: type).hasPrefix("Array") ? "a list" : "an object"
        }
    }
}
