import Domain
import Foundation

/// Number formatting for presentation texts, in the user's locale (tests pass a fixed one).
public struct Format: Sendable {
    public let locale: Locale

    public var weightUnit: WeightUnit

    public init(locale: Locale = .current, weightUnit: WeightUnit = .kilograms) {
        self.locale = locale
        self.weightUnit = weightUnit
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
    public func weight(_ kilograms: Double, maxFractionDigits: Int = 2) -> String {
        "\(weightNumber(kilograms, maxFractionDigits: maxFractionDigits)) \(weightUnit.symbol)"
    }

    public func weightNumber(_ kilograms: Double, maxFractionDigits: Int = 2) -> String {
        number(kilograms / weightUnit.kilogramsPerUnit, maxFractionDigits: maxFractionDigits)
    }

    /// "3:00" from seconds.
    public func minutesAndSeconds(_ seconds: Int) -> String {
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }
}
