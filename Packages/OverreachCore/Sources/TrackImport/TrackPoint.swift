import Foundation

/// One timed position read from a track file. Internal on purpose: coordinates never leave this module, because
/// they reveal where the athlete lives (docs/design/companion-walks.md#privacy).
struct TrackPoint: Equatable {
    var time: Date
    var latitude: Double
    var longitude: Double

    /// Great-circle distance in meters (haversine).
    func distance(to other: TrackPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let half = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * asin(min(1, half.squareRoot()))
    }
}
