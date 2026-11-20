import Domain
import Foundation
@testable import PresentationKit
import Testing

@Suite("Further reading (ADR-0024)")
struct FurtherReadingTests {
    /// `docs/evidence.md`, found from this file's path.
    private func registerKeys() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("docs/evidence.md"), encoding: .utf8)
        let headings = text.split(separator: "\n").filter { $0.hasPrefix("### `") }
        return Set(headings.compactMap { $0.split(separator: "`").dropFirst().first.map(String.init) })
    }

    @Test func everyKeyIsInTheEvidenceRegister() throws {
        let keys = try registerKeys()
        #expect(!keys.isEmpty)
        for key in FurtherReading.catalogue.keys {
            #expect(keys.contains(key), "\(key) is not in docs/evidence.md")
        }
    }

    @Test func linksAreHTTPSAndNeverRepeatedWithinAKey() {
        for (key, readings) in FurtherReading.catalogue {
            #expect(readings.allSatisfy { $0.url.scheme == "https" }, "\(key)")
            #expect(Set(readings.map(\.url)).count == readings.count, "\(key)")
        }
    }

    @Test func articlesThatContradictTheRegisterAreNotLinked() {
        let urls = FurtherReading.catalogue.values.flatMap { $0 }.map(\.url.absoluteString)
        // Training by cycle phase contradicts `cycle-phase-performance` (ADR-0009).
        #expect(!urls.contains { $0.contains("utiliza-tu-ciclo-menstrual") })
        #expect(FurtherReading.catalogue["cycle-phase-performance"] == nil)
    }

    @Test func theUsersLanguageComesFirst() {
        let reference = EvidenceReference(key: "proximity-to-failure", level: .strong)

        let spanish = FurtherReading.readings(for: reference, userLanguage: "es")
        let english = FurtherReading.readings(for: reference, userLanguage: "en")

        #expect(spanish.first?.languageCode == "es")
        #expect(english.first?.languageCode == "en")
        #expect(Set(spanish) == Set(english))
    }

    @Test func severalKeysAreMergedWithoutRepeatsUpToTheLimit() {
        let references = ["rir-based-rpe", "rir-estimation", "autoregulation-load", "volume-dose-response",
                          "periodization"].map { EvidenceReference(key: $0, level: .moderate) }

        let readings = FurtherReading.readings(for: references, userLanguage: "es")

        #expect(readings.count == FurtherReading.limit)
        #expect(Set(readings.map(\.url)).count == readings.count)
        #expect(readings.filter { $0.title.hasPrefix("Autorregulación") }.count == 1)
    }

    @Test func unknownKeysHaveNoReadings() {
        #expect(FurtherReading.readings(for: EvidenceReference(key: "no-such-key", level: .heuristic)).isEmpty)
    }

    @Test func theDetailNamesTheLanguageOnlyWhenItIsNotTheUsers() throws {
        let reading = try #require(FurtherReading.catalogue["proximity-to-failure"]?.first { $0.languageCode == "es" })

        #expect(reading.detail(userLanguage: "es") == "Fitness Revolucionario (Marcos Vázquez) · 2020")
        #expect(reading.detail(userLanguage: "en") == "Fitness Revolucionario (Marcos Vázquez) · 2020 · in Spanish")
    }

    @Test func aPartialMatchCarriesItsCaveat() throws {
        let intro = try #require(FurtherReading.catalogue["readiness-hrv"]?.first { $0.languageCode == "es" })
        #expect(intro.note?.hasPrefix("An older introduction") == true)
    }
}
