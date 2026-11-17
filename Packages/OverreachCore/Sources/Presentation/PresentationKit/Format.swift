import Foundation

/// Number formatting for presentation texts, in the user's locale (tests pass a fixed one).
public struct Format: Sendable {
    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// "62.5" — up to `maxFractionDigits` decimals, no trailing zeros.
    public func number(_ value: Double, maxFractionDigits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).locale(locale))
    }

    /// "62.5" with exactly `digits` decimals.
    public func fixed(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// "62.5 kg".
    public func kilograms(_ value: Double) -> String { "\(number(value)) kg" }

    /// "3:00" from seconds.
    public func minutesAndSeconds(_ seconds: Int) -> String {
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }
}
