import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// The file formats a tracker exports its location history in.
public enum TrackFormat: String, Sendable, Equatable {
    case gpx
    case kml
}

/// Why a file could not be read. Nothing is imported when one of these is thrown.
public enum TrackImportError: Error, Equatable, Sendable {
    /// The file is not well-formed XML.
    case malformed
    /// The file is XML, but neither GPX nor KML.
    case unsupportedFormat
    /// The file holds no point with a position and a time.
    case noPoints
}

struct ParsedTrack {
    var format: TrackFormat
    var points: [TrackPoint]
    /// Points dropped for a missing or invalid time or position.
    var skippedPoints: Int
}

/// Streaming GPX/KML reader built on `XMLParser`: the file is never held as a tree.
///
/// GPX: `trkpt` elements with `lat`/`lon` attributes and a `time` child.
/// KML: `gx:Track` (`when` and `gx:coord` in parallel) and `Placemark`s with a `TimeStamp` and a `Point`.
/// Routes without times (`LineString`, `rte`, `wpt`) are ignored: they cannot say when anything moved.
enum TrackParser {
    static func parse(_ data: Data) throws -> ParsedTrack {
        let delegate = TrackParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        let finished = parser.parse()
        if let format = delegate.format, !delegate.rejectedFormat, finished, delegate.rootClosed {
            return ParsedTrack(format: format, points: delegate.points, skippedPoints: delegate.skipped)
        }
        throw delegate.rejectedFormat ? TrackImportError.unsupportedFormat : TrackImportError.malformed
    }
}

private final class TrackParserDelegate: NSObject, XMLParserDelegate {
    private(set) var format: TrackFormat?
    private(set) var rejectedFormat = false
    private(set) var points: [TrackPoint] = []
    private(set) var skipped = 0
    /// False when the file ends before the root element closes: a truncated download.
    private(set) var rootClosed = false

    private var text = ""
    private var depth = 0
    private let timeParser = TrackTimeParser()

    // GPX
    private var gpxPoint: (latitude: Double, longitude: Double)?
    private var gpxTime: Date?
    private var inTrackPoint = false

    // KML gx:Track
    private var inTrack = false
    private var whens: [Date?] = []
    private var coords: [(latitude: Double, longitude: Double)?] = []

    // KML Placemark
    private var inPlacemark = false
    private var inPoint = false
    private var placemarkTime: Date?
    private var placemarkPosition: (latitude: Double, longitude: Double)?

    private static func local(_ name: String) -> String {
        name.split(separator: ":", maxSplits: 1).last.map(String.init) ?? name
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        let name = Self.local(elementName)
        depth += 1
        text = ""
        if format == nil {
            switch name {
            case "gpx": format = .gpx
            case "kml": format = .kml
            default:
                rejectedFormat = true
                parser.abortParsing()
            }
            return
        }
        switch (format, name) {
        case (.gpx, "trkpt"):
            inTrackPoint = true
            gpxTime = nil
            gpxPoint = Self.position(latitude: attributes["lat"], longitude: attributes["lon"])
        case (.kml, "Track"):
            inTrack = true
            whens = []
            coords = []
        case (.kml, "Placemark"):
            inPlacemark = true
            placemarkTime = nil
            placemarkPosition = nil
        case (.kml, "Point"): inPoint = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
        defer {
            depth -= 1
            if depth == 0 { rootClosed = true }
        }
        let name = Self.local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {
        case .gpx: endGPX(name, value)
        case .kml: endKML(name, value)
        case nil: break
        }
    }

    private func endGPX(_ name: String, _ value: String) {
        switch name {
        case "time" where inTrackPoint:
            gpxTime = timeParser.date(value)
        case "trkpt":
            inTrackPoint = false
            emit(time: gpxTime, position: gpxPoint)
        default: break
        }
    }

    private func endKML(_ name: String, _ value: String) {
        switch name {
        case "when" where inTrack:
            whens.append(timeParser.date(value))
        case "coord" where inTrack:
            coords.append(Self.spaceSeparated(value))
        case "Track":
            inTrack = false
            for index in 0..<max(whens.count, coords.count) {
                emit(
                    time: index < whens.count ? whens[index] : nil, position: index < coords.count ? coords[index] : nil
                )
            }
        case "when" where inPlacemark:
            placemarkTime = timeParser.date(value)
        case "coordinates" where inPlacemark && inPoint:
            placemarkPosition = Self.commaSeparated(value)
            if placemarkPosition == nil { placemarkTime = nil }
        case "Point": inPoint = false
        case "Placemark":
            inPlacemark = false
            // A placemark with neither a time nor a point (a folder name, a route) is not a point.
            if placemarkTime != nil || placemarkPosition != nil {
                emit(time: placemarkTime, position: placemarkPosition)
            }
        default: break
        }
    }

    private func emit(time: Date?, position: (latitude: Double, longitude: Double)?) {
        guard let time, let position else {
            skipped += 1
            return
        }
        points.append(TrackPoint(time: time, latitude: position.latitude, longitude: position.longitude))
    }

    private static func position(latitude: String?, longitude: String?) -> (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude, let lat = Double(latitude), let lon = Double(longitude),
            (-90...90).contains(lat), (-180...180).contains(lon)
        else { return nil }
        return (lat, lon)
    }

    /// KML writes positions as `longitude latitude [altitude]` in `gx:coord` and with commas in `coordinates`.
    private static func spaceSeparated(_ value: String) -> (latitude: Double, longitude: Double)? {
        let parts = value.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard parts.count >= 2 else { return nil }
        return position(latitude: String(parts[1]), longitude: String(parts[0]))
    }

    private static func commaSeparated(_ value: String) -> (latitude: Double, longitude: Double)? {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2 else { return nil }
        return position(latitude: parts[1], longitude: parts[0])
    }
}

/// ISO 8601 times with a `Z` or an offset, with or without fractions. A time without a zone is read as UTC.
private final class TrackTimeParser {
    private let plain = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func date(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        if let date = plain.date(from: value) ?? fractional.date(from: value) { return date }
        // No zone designator: "2025-03-01T10:00:00" or with fractions.
        let hasZone = value.hasSuffix("Z") || value.dropFirst(10).contains("+") || value.dropFirst(11).contains("-")
        guard !hasZone else { return nil }
        let utc = value + "Z"
        return plain.date(from: utc) ?? fractional.date(from: utc)
    }
}
