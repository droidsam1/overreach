import Domain
import Foundation

/// Crosses the Garmin and weather source boundary with only the run's start hour and a coarse area.
struct GarminRunWeather: Sendable {
    let weather: any WeatherSource
    let tracks: any RunningTrackSource

    func weather(for run: RunActivity) async -> WeatherHour? {
        guard run.source == .garmin, run.kind == .training || run.kind == .race,
              await weather.isConfigured(), let track = await tracks.runningTrack(for: run) else { return nil }
        let area = track.samples.lazy.compactMap { sample -> WeatherArea? in
            guard let latitude = sample.latitude, let longitude = sample.longitude else { return nil }
            return WeatherArea(latitude: latitude, longitude: longitude)
        }.first
        guard let area else { return nil }
        return await weather.historical(for: area, at: run.startedAt)
    }
}
