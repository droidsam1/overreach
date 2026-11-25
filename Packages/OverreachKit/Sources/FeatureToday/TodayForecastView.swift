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
                        Label("Weather settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .navigationTitle("Weather today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .refreshable { await model.load() }
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
                Button("Remove saved area", role: .destructive) { model.removeArea() }
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
            Image(systemName: hour.symbol).accessibilityHidden(true)
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
