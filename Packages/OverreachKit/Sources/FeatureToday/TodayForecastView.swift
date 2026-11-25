import DesignSystem
import SwiftUI
import TodayPresentation

struct TodayForecastView<Settings: View>: View {
    let model: TodayForecastModel
    @ViewBuilder let settings: () -> Settings

    var body: some View {
        List {
            if model.isConfigured {
                forecast
            } else {
                Section {
                    Text("Connect OpenWeather to see an hourly forecast for running and walks.")
                    NavigationLink {
                        settings()
                    } label: {
                        Label("Set up weather", systemImage: "key")
                    }
                }
            }
        }
        .navigationTitle("Weather today")
        .task { await model.load() }
        .refreshable { await model.load(forceRefresh: true) }
    }

    @ViewBuilder private var forecast: some View {
        if model.area != nil {
            if model.hours.isEmpty {
                if model.isLoading {
                    ProgressView("Loading…")
                } else {
                    Text("The forecast is unavailable. Try refreshing later.")
                }
            } else {
                if let updated = model.updatedText {
                    Text(verbatim: updated).font(.footnote).foregroundStyle(.secondary)
                }
                windows("Likely dry", model.dryWindows, symbol: "drop.degreesign.slash")
                windows("Clear or mostly sunny", model.sunnyWindows, symbol: "sun.max")
                Section("Hourly forecast") {
                    ForEach(model.hours) { hour in hourRow(hour) }
                }
                if let url = TodayForecastModel.attributionURL {
                    Section {
                        Link("Weather data from OpenWeather", destination: url)
                    }
                }
            }
        }
        Section {
            Button {
                Task { await model.useCurrentArea() }
            } label: {
                Label("Use my approximate location", systemImage: "location")
            }
            .disabled(model.isLocating)
            if model.isLocating { ProgressView("Finding your area…") }
            if model.locationUnavailable {
                Text("Location unavailable. Check location access in iPhone Settings and try again.")
                    .foregroundStyle(.secondary)
            }
            if model.area != nil {
                Button("Remove saved area", role: .destructive) { Task { await model.removeArea() } }
                    .disabled(model.isLocating)
            }
        } footer: {
            Text("Overreach saves a coarse area for the forecast. Update it if you move to another area.")
        }
    }

    @ViewBuilder private func windows(
        _ title: LocalizedStringKey, _ windows: [TodayForecastModel.Window], symbol: String
    ) -> some View {
        if !windows.isEmpty {
            Section(title) {
                ForEach(windows) { window in
                    Label {
                        let start = window.start.formatted(.dateTime.hour().minute())
                        let end = window.end.formatted(.dateTime.hour().minute())
                        Text(verbatim: "\(start) – \(end)")
                    } icon: {
                        Image(systemName: symbol).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func hourRow(_ hour: TodayForecastModel.Hour) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            WeatherSymbol(systemName: hour.symbol, tone: hour.sky?.tone ?? .cloudy)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(hour.id, format: .dateTime.hour().minute()).font(.headline)
                if let conditions = hour.conditions {
                    Text(conditions).foregroundStyle(.secondary)
                }
                if let precipitation = hour.precipitation {
                    Text(precipitation).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.small)
            if let temperature = hour.temperature { Text(temperature).monospacedDigit() }
        }
        .accessibilityElement(children: .combine)
    }
}

extension TodayForecastModel.Sky {
    var tone: WeatherTone {
        switch self {
        case .clear: .clear
        case .clearNight: .clearNight
        case .partlyCloudy: .partlyCloudy
        case .partlyCloudyNight: .partlyCloudyNight
        case .cloudy: .cloudy
        case .rain: .rain
        case .thunderstorm: .thunderstorm
        case .snow: .snow
        case .fog: .fog
        }
    }
}

/// The weather button of the Today toolbar: grey when weather is not set up, coloured with the temperature when a
/// forecast is shown, and a small progress or warning badge while loading or when the forecast failed.
struct TodayWeatherToolbarLabel: View {
    let model: TodayForecastModel

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            switch model.toolbarState {
            case .notConnected, .needsArea:
                WeatherSymbol(systemName: "cloud.sun", tone: .muted)
            case .loading:
                WeatherSymbol(systemName: "cloud.sun", tone: .muted)
                ProgressView().controlSize(.mini)
            case .unavailable:
                WeatherSymbol(systemName: "cloud.sun", tone: .muted)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(StatusTone.caution.color)
                    .accessibilityHidden(true)
            case .ready:
                WeatherSymbol(systemName: model.toolbarSymbol, tone: model.toolbarSky?.tone ?? .cloudy)
                if let temperature = model.toolbarTemperature {
                    Text(temperature).monospacedDigit()
                }
            }
        }
    }
}
