import Domain
import Foundation

/// Search used by every list: case-, accent- and spacing-insensitive "contains" over several names.
public enum SearchText {
    /// Lowercased, accent-free, single-spaced form of `text`.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Whether any of `names` contains `query`. An empty query matches everything.
    public static func matches(_ query: String, _ names: [String]) -> Bool {
        let needle = normalize(query)
        guard !needle.isEmpty else { return true }
        return names.contains { normalize($0).contains(needle) }
    }

    /// Exercises whose name or aliases contain `query`, in their original order.
    public static func filter(_ exercises: [Exercise], by query: String) -> [Exercise] {
        exercises.filter { matches(query, [$0.name] + $0.aliases.sorted()) }
    }
}
