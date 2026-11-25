import Domain
import Foundation
@testable import GarminImport
import Testing

struct GarminFITSyncTests {
    // One synthetic FIT record (143 bpm), with stored and deflated ZIP envelopes.
    private static let raw = "DCAAABIAAAAuRklUQAAAFAAC/QSGAwECAAUAAACP2PM="
    private static let stored =
        "UEsDBBQAAAAAAINreV1qFEPMIAAAACAAAAAOAAAAMV9BQ1RJVklUWS5maXQMIAAAEgAAAC5GSVRAAAAUAAL9BIYD"
        + "AQIABQAAAI/Y81BLAQIUABQAAAAAAINreV1qFEPMIAAAACAAAAAOAAAAAAAAAAAAAACAAQAAAAAxX0FDVElWSVRZ"
        + "LmZpdFBLBQYAAAAAAQABADwAAABMAAAAAAA="
    private static let deflated =
        "UEsDBBQAAAAIAINreV1qFEPMIQAAACAAAAAOAAAAMV9BQ1RJVklUWS5maXTjUWBgEGJgYNBz8wxxYGAQYWD6y9LG"
        + "zMjEwAoU7L/xGQBQSwECFAAUAAAACACDa3ldahRDzCEAAAAgAAAADgAAAAAAAAAAAAAAgAEAAAAAMV9BQ1RJVklU"
        + "WS5maXRQSwUGAAAAAAEAAQA8AAAATQAAAAAA"

    @Test func readsTheGarminEnvelopesAndRejectsBadArchiveChecksums() throws {
        let expected = try GarminFITArchive.track(from: #require(Data(base64Encoded: Self.raw)))
        let compressed = try #require(Data(base64Encoded: Self.deflated))
        #expect(try GarminFITArchive.track(from: compressed) == expected)
        let stored = try #require(Data(base64Encoded: Self.stored))
        #expect(try GarminFITArchive.track(from: stored) == expected)

        var wrongCRC = stored
        wrongCRC[92] ^= 1
        #expect(throws: GarminFITArchive.ArchiveError.self) { try GarminFITArchive.track(from: wrongCRC) }
        #expect(throws: GarminFITArchive.ArchiveError.self) {
            try GarminFITArchive.track(from: compressed.dropLast())
        }
    }

    @Test func syncDownloadsBoundedTracksAndReadsTheLocalCacheOffline() async throws {
        let garmin = FakeGarmin()
        let cache = MemoryCache()
        let secrets = MemorySecrets()
        let service = makeService(garmin: garmin, secrets: secrets, cache: cache)
        let payload = """
            [
             {"activityId":31,"duration":600,"activityType":{"typeKey":"running"},"startTimeGMT":"2026-01-06 08:00:00"},
             {"activityId":32,"duration":600,"activityType":{"typeKey":"running"},"startTimeGMT":"2026-01-07 08:00:00"},
             {"activityId":33,"duration":600,"activityType":{"typeKey":"running"},"startTimeGMT":"2026-01-08 08:00:00"},
             {"activityId":34,"duration":600,"activityType":{"typeKey":"strength_training"},
              "startTimeGMT":"2026-01-08 07:00:00"}
            ]
            """
        let zip = try #require(Data(base64Encoded: Self.deflated))
        await garmin.setActivityPage(start: 0, body: Data(payload.utf8))
        await garmin.respond(to: "/activity/33", with: GarminHTTPResponse(status: 200, body: zip))
        try await service.connect(key: "valid-key-0123456789", lifetime: .recommended)
        _ = try await service.sync { _ in }

        let requests = await garmin.requests.filter { $0.path.hasPrefix("/download-service/") }
        #expect(requests.map(\.path) == ["/download-service/files/activity/33", "/download-service/files/activity/32"])
        #expect(requests.first?.headers["Accept"]?.contains("application/x-zip-compressed") == true)

        let runs = try await service.runs(from: .distantPast, to: .distantFuture)
        let run = try #require(runs.first { $0.id == "33" })
        let track = try #require(await service.runningTrack(for: run))
        #expect(track.samples.first?.heartRateBPM == 143)
        #expect(track.heartRateSensorID == nil)

        _ = try await service.sync { _ in }
        let repeated = await garmin.requests.filter { $0.path.hasPrefix("/download-service/") }
        #expect(repeated.count == 3)
        #expect(repeated.last?.path.hasSuffix("/31") == true)

        let storedCache = try #require(await cache.cache)
        let encoded = try JSONEncoder().encode(storedCache)
        await cache.save(try JSONDecoder().decode(GarminCache.self, from: encoded))
        await garmin.setOffline(true)
        let reopened = makeService(garmin: garmin, secrets: secrets, cache: cache)
        #expect(await reopened.runningTrack(for: run) == track)
    }

    @Test func optionalFITRateLimitPreservesTheSummaryAndStopsFurtherDownloads() async throws {
        let garmin = FakeGarmin()
        let service = makeService(garmin: garmin)
        await garmin.respond(to: "/activity/10000004", with: GarminHTTPResponse(status: 429))

        try await service.connect(key: "valid-key-0123456789", lifetime: .recommended)
        let summary = try await service.sync { _ in }

        #expect(summary.runs == 4)
        #expect(await service.connection()?.lastSync == fixtureNow)
        let requests = await garmin.requests.filter { $0.path.hasPrefix("/download-service/") }
        #expect(requests.count == 3)  // The client retries twice before pausing optional downloads.
        #expect(requests.allSatisfy { $0.path == "/download-service/files/activity/10000004" })
    }
}
