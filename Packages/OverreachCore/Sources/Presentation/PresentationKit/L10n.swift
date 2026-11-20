import Foundation

/// Text produced by presentation models (rule explanations, summaries, error messages).
///
/// On Apple platforms it is looked up in the app's String Catalog; on Linux (tests) the English text is used.
/// Static UI text (titles, button labels) stays in the views as `LocalizedStringKey` (ADR-0015).
public enum L10n {
    public static func text(_ english: String) -> String {
        #if canImport(Darwin)
        String(localized: String.LocalizationValue(english))
        #else
        english
        #endif
    }

    /// The language the app shows ("en", "es", "gl"), e.g. to put further reading in that language first.
    public static var languageCode: String {
        #if canImport(Darwin)
        Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en"
        #else
        "en"
        #endif
    }

    /// A translated sentence with values: `{1}`, `{2}`… are replaced by `values`, in the order each language needs.
    /// The template is the catalog key, so never build it by interpolation.
    public static func format(_ template: String, _ values: any CustomStringConvertible...) -> String {
        fill(text(template), with: values.map(\.description))
    }

    /// One pass over the template, so a value that looks like a placeholder is left alone.
    static func fill(_ template: String, with values: [String]) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            if let close = rest[afterOpen...].firstIndex(of: "}"),
               let number = Int(rest[afterOpen..<close]), values.indices.contains(number - 1) {
                result += values[number - 1]
                rest = rest[rest.index(after: close)...]
            } else {
                result += "{"
                rest = rest[afterOpen...]
            }
        }
        return result + rest
    }
}
