import Foundation

/// Text produced by presentation models (rule explanations, summaries, error messages).
///
/// On Apple platforms it is looked up in the app's String Catalog; on Linux (tests) the English text is used.
/// Static UI text (titles, button labels) stays in the views as `LocalizedStringKey`.
public enum L10n {
    public static func text(_ english: String) -> String {
        #if canImport(Darwin)
        String(localized: String.LocalizationValue(english))
        #else
        english
        #endif
    }
}
