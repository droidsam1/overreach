import CoreLocation
import Domain
import Foundation
import TodayPresentation

extension AppContainer {
    func makeTodayForecastModel() -> TodayForecastModel? {
        guard let weather else { return nil }
        let key = "today.weather.area"
        let defaults = UserDefaults.standard
        let saved = defaults.array(forKey: key) as? [Double]
        let area = saved.flatMap { values in
            values.count == 2 ? WeatherArea(latitude: values[0], longitude: values[1]) : nil
        }
        let locator = ForecastAreaLocator()
        return TodayForecastModel(source: weather, area: area) {
            await locator.currentArea()
        } storeArea: { area in
            if let area {
                defaults.set([area.latitude, area.longitude], forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

@MainActor
private final class ForecastAreaLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<WeatherArea?, Never>?
    private var requestingLocation = false

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.delegate = self
    }

    func currentArea() async -> WeatherArea? {
        guard pending == nil else { return nil }
        return await withCheckedContinuation { continuation in
            pending = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            default: authorizationChanged()
            }
        }
    }

    private func authorizationChanged() {
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestingLocation else { return }
            requestingLocation = true
            manager.requestLocation()
        case .notDetermined:
            break
        default:
            finish(nil)
        }
    }

    private func finish(_ area: WeatherArea?) {
        let continuation = pending
        pending = nil
        requestingLocation = false
        continuation?.resume(returning: area)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let area = locations.last { $0.horizontalAccuracy >= 0 }.flatMap {
            WeatherArea(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        Task { @MainActor in finish(area) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in finish(nil) }
    }
}
