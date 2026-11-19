@testable import DesignSystem
import Foundation
import Testing

@Suite("Number fields")
struct NumberTextTests {
    @Test func acceptsEitherDecimalSeparator() {
        #expect(NumberText.value(of: "47,5", allowsDecimals: true) == 47.5)
        #expect(NumberText.value(of: "47.5", allowsDecimals: true) == 47.5)
        #expect(NumberText.value(of: "47,", allowsDecimals: true) == 47)
        #expect(NumberText.value(of: " 60 ", allowsDecimals: true) == 60)
    }

    @Test func repsAreWholeNumbers() {
        #expect(NumberText.value(of: "8", allowsDecimals: false) == 8)
        #expect(NumberText.value(of: "8,5", allowsDecimals: false) == nil)
    }

    @Test func emptyOrInvalidTextClearsTheValue() {
        #expect(NumberText.value(of: "", allowsDecimals: true) == nil)
        #expect(NumberText.value(of: "abc", allowsDecimals: true) == nil)
        #expect(NumberText.value(of: "-5", allowsDecimals: true) == nil)
    }

    @Test func showsTheValueInTheUsersLocaleWithoutTrailingZeros() {
        let spanish = Locale(identifier: "es_ES")
        #expect(NumberText.text(for: 47.5, locale: spanish) == "47,5")
        #expect(NumberText.text(for: 60, locale: spanish) == "60")
        #expect(NumberText.text(for: 1250, locale: spanish) == "1250")
        #expect(NumberText.text(for: 61.25, locale: Locale(identifier: "en_US")) == "61.25")
        #expect(NumberText.text(for: nil) == "")
    }
}
