import Domain
import Foundation

/// Records decoded from one Garmin response, and how many were skipped because they could not be read.
public struct GarminDecoded<Record: Sendable>: Sendable {
    public var records: [Record]
    /// Records present in the response that could not be read (no date or id). A rise means Garmin changed something.
    public var skipped: Int

    public init(records: [Record] = [], skipped: Int = 0) {
        self.records = records
        self.skipped = skipped
    }
}

public enum GarminDecodingError: Error, Equatable {
    /// The response is not the JSON shape the endpoint documents: Garmin changed it, or this is an error page.
    case unexpectedShape(String)
}

/// Turns Garmin Personal API responses into records. Pure, so it is tested on Linux against recorded fixtures.
///
/// Tolerant by design: an empty body (HTTP 204) means no data, unknown fields are ignored, a field of an unexpected
/// type reads as missing, and a record without its date or id is skipped and counted. Only a response whose overall
/// shape is wrong throws.
public enum GarminDecoding {
    public static func hrvNights(from data: Data) throws -> GarminDecoded<GarminHRVNight> {
        guard let root = try object(data, "hrv") else { return GarminDecoded() }
        guard let root = root as? [String: Any] else { throw GarminDecodingError.unexpectedShape("hrv") }
        return decode(root["hrvSummaries"] as? [Any] ?? []) { item in
            guard let day = day(item["calendarDate"]) else { return nil }
            let baseline = item["baseline"] as? [String: Any]
            return GarminHRVNight(
                day: day,
                lastNightAverage: positive(item["lastNightAvg"]),
                lastNight5MinuteHigh: positive(item["lastNight5MinHigh"]),
                weeklyAverage: positive(item["weeklyAvg"]),
                baselineBalancedLow: positive(baseline?["balancedLow"]),
                baselineBalancedUpper: positive(baseline?["balancedUpper"]),
                status: label(item["status"])
            )
        }
    }

    public static func sleeps(from data: Data) throws -> GarminDecoded<GarminSleep> {
        guard let root = try object(data, "sleep") else { return GarminDecoded() }
        // The range endpoint returns an array; the single-day one returns one object.
        let items: [Any]
        if let array = root as? [Any] {
            items = array
        } else if let single = root as? [String: Any] {
            items = [single["dailySleepDTO"] ?? single]
        } else {
            throw GarminDecodingError.unexpectedShape("sleep")
        }
        return decode(items) { item in
            guard let day = day(item["calendarDate"]) else { return nil }
            let scores = item["sleepScores"] as? [String: Any]
            let overall = scores?["overall"] as? [String: Any]
            return GarminSleep(
                day: day,
                start: epochMilliseconds(item["sleepStartTimestampGMT"]),
                end: epochMilliseconds(item["sleepEndTimestampGMT"]),
                sleepSeconds: positive(item["sleepTimeSeconds"]),
                deepSeconds: nonNegative(item["deepSleepSeconds"]),
                lightSeconds: nonNegative(item["lightSleepSeconds"]),
                remSeconds: nonNegative(item["remSleepSeconds"]),
                awakeSeconds: nonNegative(item["awakeSleepSeconds"]),
                score: nonNegative(overall?["value"]),
                averageRespiration: positive(item["averageRespirationValue"]),
                averageSpO2: positive(item["averageSpO2Value"])
            )
        }
    }

    public static func dailySummaries(from data: Data) throws -> GarminDecoded<GarminDailySummary> {
        guard let root = try object(data, "daily summaries") else { return GarminDecoded() }
        guard let root = root as? [String: Any] else {
            throw GarminDecodingError.unexpectedShape("daily summaries")
        }
        return decode(root["data"] as? [Any] ?? []) { item in
            guard let day = day(item["calendarDate"]) else { return nil }
            let heartRate = item["heartRate"] as? [String: Any]
            let movement = item["movement"] as? [String: Any]
            let steps = movement?["steps"] as? [String: Any]
            let stress = item["stress"] as? [String: Any]
            let bodyBattery = item["bodyBattery"] as? [String: Any]
            let respiration = item["respiration"] as? [String: Any]
            let pulseOx = item["pulseOx"] as? [String: Any]
            return GarminDailySummary(
                day: day,
                restingHeartRate: positive(heartRate?["restingValue"]),
                steps: nonNegative(steps?["value"]).map { Int($0) },
                averageStress: nonNegative(stress?["avgLevel"]),
                bodyBatteryHigh: nonNegative(bodyBattery?["maxValue"]),
                bodyBatteryLow: nonNegative(bodyBattery?["minValue"]),
                averageRespiration: positive(respiration?["avgValue"]),
                averageSpO2: positive(pulseOx?["avgValue"])
            )
        }
    }

    public static func vo2Max(from data: Data) throws -> GarminDecoded<GarminVO2Max> {
        guard let root = try object(data, "VO2max") else { return GarminDecoded() }
        guard let items = root as? [Any] else { throw GarminDecodingError.unexpectedShape("VO2max") }
        return decode(items) { item in
            // Running and generic VO2max share `generic`; cycling has its own entry, not used here.
            guard let generic = item["generic"] as? [String: Any], let day = day(generic["calendarDate"]),
                let value = positive(generic["vo2MaxPreciseValue"]) ?? positive(generic["vo2MaxValue"])
            else { return nil }
            return GarminVO2Max(day: day, value: value)
        }
    }

    public static func activities(from data: Data) throws -> GarminDecoded<GarminActivity> {
        guard let root = try object(data, "activities") else { return GarminDecoded() }
        guard let items = root as? [Any] else { throw GarminDecodingError.unexpectedShape("activities") }
        return decode(items) { item in
            guard let id = identifier(item["activityId"]), let start = gmtDateTime(item["startTimeGMT"]) else {
                return nil
            }
            let type = item["activityType"] as? [String: Any]
            return GarminActivity(
                id: id,
                typeKey: type?["typeKey"] as? String,
                name: item["activityName"] as? String,
                startedAt: start,
                durationSeconds: nonNegative(item["duration"]),
                distanceMeters: nonNegative(item["distance"]),
                averageHeartRate: positive(item["averageHR"]),
                maxHeartRate: positive(item["maxHR"]),
                elevationGainMeters: nonNegative(item["elevationGain"]),
                elevationLossMeters: nonNegative(item["elevationLoss"]),
                averageRunningCadence: positive(item["averageRunningCadenceInStepsPerMinute"]),
                trainingLoad: nonNegative(item["activityTrainingLoad"]),
                aerobicTrainingEffect: nonNegative(item["aerobicTrainingEffect"]),
                anaerobicTrainingEffect: nonNegative(item["anaerobicTrainingEffect"]),
                totalSets: nonNegative(item["totalSets"]).map { Int($0) },
                totalReps: nonNegative(item["totalReps"]).map { Int($0) },
                steps: nonNegative(item["steps"]).map { Int($0) },
                lapCount: positive(item["lapCount"]).map { Int($0) },
                movingDurationSeconds: positive(item["movingDuration"]),
                runWalk: runWalk(item["splitSummaries"])
            )
        }
    }

    /// The laps of one activity (`/activity-service/activity/{id}/splits`, `lapDTOs[]`), oldest first. Laps without
    /// a distance or a time are dropped. An empty body (204) or an answer without `lapDTOs` is no laps, not an error.
    public static func laps(from data: Data) throws -> [RunLap] {
        guard let root = try object(data, "splits") else { return [] }
        if root is [Any] { return [] }
        guard let root = root as? [String: Any] else { throw GarminDecodingError.unexpectedShape("splits") }
        guard let items = root["lapDTOs"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let distance = nonNegative(item["distance"]), let duration = positive(item["duration"]),
                distance > 0
            else { return nil }
            return RunLap(
                distanceMeters: distance,
                durationSeconds: duration,
                averageHeartRate: positive(item["averageHR"]),
                maxHeartRate: positive(item["maxHR"]),
                averageCadence: positive(item["averageRunCadence"]),
                elevationGainMeters: nonNegative(item["elevationGain"]),
                elevationLossMeters: nonNegative(item["elevationLoss"])
            )
        }
    }

    /// Garmin's run/walk detection in the activity summary: `RWD_RUN`, `RWD_WALK` and `RWD_STAND` split summaries.
    /// Interval splits (`INTERVAL_*`) describe workout steps and are ignored.
    public static func runWalk(_ value: Any?) -> RunWalkSplits? {
        guard let summaries = value as? [[String: Any]] else { return nil }
        func part(_ type: String) -> RunWalkSplits.Part? {
            guard let item = summaries.first(where: { $0["splitType"] as? String == type }),
                  let distance = nonNegative(item["distance"]), let duration = nonNegative(item["duration"]),
                  distance > 0 || duration > 0 else { return nil }
            return RunWalkSplits.Part(
                distanceMeters: distance, durationSeconds: duration,
                segments: positive(item["noOfSplits"]).map { Int($0) } ?? 1,
                longestSegmentMeters: positive(item["maxDistanceWithPrecision"]) ?? positive(item["maxDistance"]),
                averageCadence: positive(item["avgStepFrequency"])
            )
        }
        let splits = RunWalkSplits(running: part("RWD_RUN"), walking: part("RWD_WALK"), standing: part("RWD_STAND"))
        return splits.running == nil && splits.walking == nil ? nil : splits
    }

    // MARK: Helpers

    /// nil for an empty body (204: no data).
    private static func object(_ data: Data, _ endpoint: String) throws -> Any? {
        guard !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw GarminDecodingError.unexpectedShape(endpoint)
        }
    }

    private static func decode<Record>(
        _ items: [Any], _ transform: ([String: Any]) -> Record?
    ) -> GarminDecoded<Record> {
        var result = GarminDecoded<Record>()
        for item in items {
            if let item = item as? [String: Any], let record = transform(item) {
                result.records.append(record)
            } else {
                result.skipped += 1
            }
        }
        return result
    }

    /// A number, whether Garmin sent it as an integer, a decimal or a numeric string.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue.isFinite ? number.doubleValue : nil
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func nonNegative(_ value: Any?) -> Double? {
        number(value).flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func positive(_ value: Any?) -> Double? {
        number(value).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func label(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text != "NONE", text != "INVALID" else { return nil }
        return text
    }

    private static func identifier(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        guard let number = number(value), number >= 0, number == number.rounded() else { return nil }
        return String(Int64(number))
    }

    /// `yyyy-MM-dd`, as Garmin writes calendar dates.
    static func day(_ value: Any?) -> CalendarDay? {
        guard let text = value as? String else { return nil }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return CalendarDay(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func epochMilliseconds(_ value: Any?) -> Date? {
        guard let milliseconds = number(value), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    /// Activity times are `yyyy-MM-dd HH:mm:ss` in GMT, without a zone (sometimes with `T` or fractions).
    static func gmtDateTime(_ value: Any?) -> Date? {
        guard let text = value as? String, let day = day(text) else { return nil }
        let time = text.dropFirst(11).prefix(8).split(separator: ":").compactMap { Int($0) }
        guard time.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: time[0], minute: time[1], second: time[2]
        ))
    }
}
