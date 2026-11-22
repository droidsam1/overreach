import Foundation

/// Synthetic tracks. Never a real export: they would reveal where someone lives.
struct FixturePoint {
    var time: Date
    var latitude: Double
    var longitude: Double
}

enum TrackFixtures {
    static let origin = Date(timeIntervalSince1970: 1_760_000_000)  // an arbitrary instant
    /// About 1 m of latitude, in degrees.
    static let meter = 1.0 / 111_320.0

    /// Points every `interval` seconds, moving north at `speed` m/s from `start` for `duration` seconds.
    static func walk(
        from start: Date, duration: TimeInterval, interval: TimeInterval, speed: Double = 1.2, startMeters: Double = 0
    ) -> [FixturePoint] {
        stride(from: 0.0, through: duration, by: interval).map { offset in
            FixturePoint(
                time: start.addingTimeInterval(offset), latitude: 40 + (startMeters + speed * offset) * meter,
                longitude: -3)
        }
    }

    /// A tracker lying at one place, with a few meters of GPS noise.
    static func stationary(from start: Date, duration: TimeInterval, interval: TimeInterval) -> [FixturePoint] {
        stride(from: 0.0, through: duration, by: interval).enumerated().map { index, offset in
            let jitter = index.isMultiple(of: 2) ? 2.0 : -2.0
            return FixturePoint(time: start.addingTimeInterval(offset), latitude: 40 + jitter * meter, longitude: -3)
        }
    }

    static func gpx(_ points: [FixturePoint], offsetHours: Int = 0, extra: String = "") -> Data {
        var body = ""
        for point in points {
            body += "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>"
            body += iso(point.time, offsetHours: offsetHours) + "</time></trkpt>\n"
        }
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="synthetic" xmlns="http://www.topografix.com/GPX/1/1">
            <trk><name>Synthetic</name><trkseg>
            \(body)\(extra)</trkseg></trk></gpx>
            """
        return Data(xml.utf8)
    }

    static func kmlTrack(_ points: [FixturePoint]) -> Data {
        var body = ""
        for point in points { body += "<when>\(iso(point.time))</when>\n" }
        for point in points { body += "<gx:coord>\(point.longitude) \(point.latitude) 0</gx:coord>\n" }
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
            <Document><Placemark><gx:Track>
            \(body)</gx:Track></Placemark></Document></kml>
            """
        return Data(xml.utf8)
    }

    static func kmlPlacemarks(_ points: [FixturePoint]) -> Data {
        var body = ""
        for point in points {
            body += "<Placemark><TimeStamp><when>\(iso(point.time))</when></TimeStamp>"
            body += "<Point><coordinates>\(point.longitude),\(point.latitude),0</coordinates></Point></Placemark>\n"
        }
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <kml xmlns="http://www.opengis.net/kml/2.2"><Document>\(body)</Document></kml>
            """
        return Data(xml.utf8)
    }

    static func iso(_ date: Date, offsetHours: Int = 0) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: offsetHours * 3600)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
