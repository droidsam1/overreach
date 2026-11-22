import Domain
import Foundation
import Testing

@testable import TrackImport

@Suite("TrackImport")
struct TrackImportTests {
    private let origin = TrackFixtures.origin

    // MARK: - Movement detection

    @Test("Dense Live mode: one confident window with its distance")
    func denseWalk() throws {
        let points = TrackFixtures.walk(from: origin, duration: 20 * 60, interval: 3)
        let result = try TrackImport.read(TrackFixtures.gpx(points))
        let window = try #require(result.windows.first)
        #expect(result.windows.count == 1)
        #expect(window.confidence == .normal)
        #expect(abs(window.start.timeIntervalSince(origin)) < 1)
        #expect(abs(window.end.timeIntervalSince(origin.addingTimeInterval(1200))) < 30)
        #expect(abs(window.distanceMeters - 1.2 * 1200) < 60)
    }

    @Test("Sparse default mode: a 30-minute walk reported every 10 minutes is a low-confidence window")
    func sparseWalk() throws {
        let points = TrackFixtures.walk(from: origin, duration: 30 * 60, interval: 10 * 60, speed: 1.0)
        let window = try #require(try TrackImport.read(TrackFixtures.gpx(points)).windows.first)
        #expect(window.confidence == .low)
        #expect(window.end.timeIntervalSince(window.start) == 1800)
    }

    @Test("A tracker standing at home, with GPS noise, makes no window")
    func stationaryAtHome() throws {
        for interval in [3.0, 120.0, 600.0] {
            let points = TrackFixtures.stationary(from: origin, duration: 8 * 3600, interval: interval)
            let result = try TrackImport.read(TrackFixtures.gpx(points))
            #expect(result.windows.isEmpty, "interval \(interval)")
        }
    }

    @Test("Movement shorter than eight minutes is not a window")
    func tooShort() throws {
        let points = TrackFixtures.walk(from: origin, duration: 7 * 60, interval: 30)
        #expect(try TrackImport.read(TrackFixtures.gpx(points)).windows.isEmpty)
    }

    @Test("Runs separated by a gap of five minutes or less join; longer gaps split them")
    func gaps() throws {
        let first = TrackFixtures.walk(from: origin, duration: 10 * 60, interval: 30)
        let secondStart = origin.addingTimeInterval(10 * 60 + 4 * 60)
        let second = TrackFixtures.walk(from: secondStart, duration: 10 * 60, interval: 30, startMeters: 720)
        // The dog stands still for 4 minutes between the runs.
        let standing = FixturePoint(
            time: origin.addingTimeInterval(10 * 60 + 90), latitude: first.last?.latitude ?? 0, longitude: -3)
        let joined = try TrackImport.read(TrackFixtures.gpx(first + [standing] + second))
        #expect(joined.windows.count == 1)

        let farSecond = TrackFixtures.walk(
            from: origin.addingTimeInterval(10 * 60 + 20 * 60), duration: 10 * 60, interval: 30, startMeters: 720)
        let split = try TrackImport.read(TrackFixtures.gpx(first + farSecond))
        #expect(split.windows.count == 2)
    }

    @Test("A silence of hours between two far-apart points is not movement")
    func silenceIsNotMovement() throws {
        let points = [
            FixturePoint(time: origin, latitude: 40, longitude: -3),
            FixturePoint(time: origin.addingTimeInterval(6 * 3600), latitude: 40.1, longitude: -3),
        ]
        #expect(try TrackImport.read(TrackFixtures.gpx(points)).windows.isEmpty)
    }

    @Test("Points out of order and duplicated give the same windows")
    func orderDoesNotMatter() throws {
        let points = TrackFixtures.walk(from: origin, duration: 15 * 60, interval: 60)
        let expected = try TrackImport.read(TrackFixtures.gpx(points)).windows
        let shuffled = Array((points + points).reversed())
        #expect(try TrackImport.read(TrackFixtures.gpx(shuffled)).windows == expected)
    }

    // MARK: - Formats and times

    @Test("The same walk read from GPX, KML tracks and KML placemarks gives the same window")
    func formats() throws {
        let points = TrackFixtures.walk(from: origin, duration: 15 * 60, interval: 60)
        let gpx = try TrackImport.read(TrackFixtures.gpx(points))
        let track = try TrackImport.read(TrackFixtures.kmlTrack(points))
        let placemarks = try TrackImport.read(TrackFixtures.kmlPlacemarks(points))
        #expect(gpx.format == .gpx && track.format == .kml && placemarks.format == .kml)
        #expect(gpx.windows.count == 1)
        #expect(track.windows == gpx.windows)
        #expect(placemarks.windows == gpx.windows)
        #expect(gpx.coveredRange == origin...origin.addingTimeInterval(900))
    }

    @Test("Timezone offsets and fractional seconds are read as the same instants")
    func timezones() throws {
        let points = TrackFixtures.walk(from: origin, duration: 15 * 60, interval: 60)
        let utc = try TrackImport.read(TrackFixtures.gpx(points))
        let madrid = try TrackImport.read(TrackFixtures.gpx(points, offsetHours: 2))
        let newYork = try TrackImport.read(TrackFixtures.gpx(points, offsetHours: -5))
        #expect(madrid.windows == utc.windows)
        #expect(newYork.windows == utc.windows)

        let fractional = String(decoding: TrackFixtures.gpx(points), as: UTF8.self)
            .replacingOccurrences(of: "Z</time>", with: ".250Z</time>")
        let result = try TrackImport.read(Data(fractional.utf8))
        #expect(result.windows.count == 1)
        #expect(result.skippedPoints == 0)
    }

    // MARK: - Bad input

    @Test("Malformed XML is a typed error")
    func malformed() {
        let truncated = Data(
            String(
                decoding: TrackFixtures.gpx(TrackFixtures.walk(from: origin, duration: 600, interval: 30)),
                as: UTF8.self
            ).dropLast(40).utf8)
        #expect(throws: TrackImportError.malformed) { try TrackImport.read(truncated) }
        #expect(throws: TrackImportError.malformed) { try TrackImport.read(Data("not xml at all".utf8)) }
        #expect(throws: TrackImportError.malformed) { try TrackImport.read(Data()) }
    }

    @Test("XML that is neither GPX nor KML is refused")
    func unsupported() {
        #expect(throws: TrackImportError.unsupportedFormat) { try TrackImport.read(Data("<html><body/></html>".utf8)) }
    }

    @Test("A file without usable points is refused")
    func noPoints() {
        let empty = Data("<gpx version=\"1.1\"><trk><trkseg/></trk></gpx>".utf8)
        #expect(throws: TrackImportError.noPoints) { try TrackImport.read(empty) }
    }

    @Test("A malformed point is skipped and counted; the rest still imports")
    func badPoints() throws {
        let points = TrackFixtures.walk(from: origin, duration: 15 * 60, interval: 60)
        let extra = """
            <trkpt lat="abc" lon="-3"><time>2025-01-01T10:00:00Z</time></trkpt>
            <trkpt lat="95" lon="-3"><time>2025-01-01T10:00:00Z</time></trkpt>
            <trkpt lat="40" lon="-3"></trkpt>
            <trkpt lat="40" lon="-3"><time>yesterday</time></trkpt>
            """
        let result = try TrackImport.read(TrackFixtures.gpx(points, extra: extra))
        #expect(result.skippedPoints == 4)
        #expect(result.pointCount == points.count)
        #expect(result.windows.count == 1)
    }

    // MARK: - Privacy and size

    @Test("The result carries no coordinates")
    func noCoordinates() throws {
        let result = try TrackImport.read(
            TrackFixtures.gpx(TrackFixtures.walk(from: origin, duration: 900, interval: 30)))
        let dump = String(describing: result)
        #expect(!dump.contains("latitude") && !dump.contains("longitude"))
        let mirror = Mirror(reflecting: result.windows[0]).children.compactMap(\.label)
        #expect(Set(mirror) == ["start", "end", "distanceMeters", "confidence"])
    }

    @Test("A 60-day file finishes within the time budget")
    func sixtyDays() throws {
        var points: [FixturePoint] = []
        for day in 0..<60 {
            let dayStart = origin.addingTimeInterval(Double(day) * 86_400)
            points += TrackFixtures.stationary(from: dayStart, duration: 6 * 3600, interval: 600)
            points += TrackFixtures.walk(
                from: dayStart.addingTimeInterval(7 * 3600), duration: 30 * 60, interval: 120)
            points += TrackFixtures.stationary(
                from: dayStart.addingTimeInterval(8 * 3600), duration: 12 * 3600, interval: 600)
        }
        let data = TrackFixtures.gpx(points)
        let started = Date()
        let result = try TrackImport.read(data)
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(result.windows.count == 60)
        #expect(result.pointCount == points.count)
    }

    // MARK: - Preview and idempotence

    private func walk(at offset: TimeInterval, minutes: Double = 20, companion: Bool = false) -> WalkBout {
        WalkBout(
            start: origin.addingTimeInterval(offset), durationSeconds: minutes * 60, source: .garmin,
            companion: companion ? .dog : nil, companionSource: companion ? .manual : nil)
    }

    @Test("The preview says which walks a window tags and which are already tagged")
    func preview() throws {
        let morning = TrackFixtures.walk(from: origin, duration: 20 * 60, interval: 30)
        let tagged = TrackFixtures.walk(from: origin.addingTimeInterval(4 * 3600), duration: 20 * 60, interval: 30)
        let result = try TrackImport.read(TrackFixtures.gpx(morning + tagged))
        let walks = [walk(at: 0), walk(at: 4 * 3600, companion: true), walk(at: 2 * 3600)]
        let preview = TrackImportPreview(result: result, walks: walks)
        #expect(preview.windows.count == 2)
        #expect(preview.walksToTag == [WalkKey(walks[0])])
        #expect(preview.alreadyTaggedCount == 1)
        #expect(preview.matchingWindowCount == 2)
        #expect(!preview.isEmpty)
    }

    @Test("Importing twice changes nothing, and a walk answered by hand keeps its answer")
    func idempotent() throws {
        let points =
            TrackFixtures.walk(from: origin, duration: 20 * 60, interval: 30)
            + TrackFixtures.walk(from: origin.addingTimeInterval(4 * 3600), duration: 20 * 60, interval: 30)
        let result = try TrackImport.read(TrackFixtures.gpx(points))
        let walks = [walk(at: 0), walk(at: 4 * 3600)]
        let answers = [WalkCompanionAnswer(walk: walks[1], withCompanion: false)]

        let once = CompanionWalkMatching.tagging(walks, answers: answers, windows: result.companionWindows)
        #expect(once[0].companion == .dog && once[0].companionSource == .trackerExport)
        #expect(once[1].companion == nil)

        // The same export again, and an overlapping one, on the already tagged walks.
        let twice = CompanionWalkMatching.tagging(once, answers: answers, windows: result.companionWindows)
        #expect(twice == once)
        let overlapping = try TrackImport.read(TrackFixtures.gpx(Array(points.prefix(points.count / 2 + 5))))
        let thrice = CompanionWalkMatching.tagging(
            twice, answers: answers, windows: result.companionWindows + overlapping.companionWindows)
        #expect(thrice == once)

        let preview = TrackImportPreview(result: result, walks: once, answers: answers)
        #expect(preview.isEmpty)
        #expect(preview.alreadyTaggedCount == 1)
    }

    @Test("Windows of the same minute share a key")
    func windowKey() {
        let first = MovementWindow(
            start: origin, end: origin.addingTimeInterval(900), distanceMeters: 1000, confidence: .normal)
        let second = MovementWindow(
            start: origin.addingTimeInterval(5), end: origin.addingTimeInterval(905), distanceMeters: 990,
            confidence: .low)
        #expect(first.key == second.key)
    }
}
