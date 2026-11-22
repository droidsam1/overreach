import Domain
import Foundation

/// What reading one export gives. No coordinates: they are dropped as soon as the windows are computed.
public struct TrackImportResult: Equatable, Sendable {
    public var format: TrackFormat
    /// First to last point time: the period the file speaks about. Windows only tag walks inside it.
    public var coveredRange: ClosedRange<Date>
    public var windows: [MovementWindow]
    public var pointCount: Int
    /// Points dropped for a missing or invalid time or position.
    public var skippedPoints: Int

    /// The windows as the matcher takes them.
    public var companionWindows: [CompanionWindow] { windows.map(\.companionWindow) }
}

/// Reads a tracker's GPX/KML location export into movement windows (ADR-0039, `docs/design/companion-walks.md`).
///
/// Pure and offline. A malformed file throws and imports nothing; a malformed point is skipped and counted.
public enum TrackImport {
    public static func read(_ data: Data) throws -> TrackImportResult {
        let track = try TrackParser.parse(data)
        guard let first = track.points.map(\.time).min(), let last = track.points.map(\.time).max() else {
            throw TrackImportError.noPoints
        }
        return TrackImportResult(
            format: track.format,
            coveredRange: first...last,
            windows: MovementDetection.windows(from: track.points),
            pointCount: track.points.count,
            skippedPoints: track.skippedPoints
        )
    }
}
