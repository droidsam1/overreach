import Foundation
import SettingsPresentation
import SwiftUI

public struct WeatherSettingsView: View {
    let model: WeatherSettingsModel
    @State private var key = ""

    public init(model: WeatherSettingsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                Text("Weather uses the approximate area and time of eligible outdoor runs.")
                Text("Set your OpenWeather One Call daily limit to 1,000 or fewer to avoid charges.")
                SecureField("OpenWeather API key", text: $key)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Button("Save weather key") {
                    Task {
                        await model.save(key)
                        if model.errorMessage == nil { key = "" }
                    }
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
                if model.isConfigured {
                    Button("Disconnect weather", role: .destructive) {
                        Task { await model.disconnect() }
                    }
                    .disabled(model.isSaving)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                }
            } header: {
                Text("OpenWeather")
            }
        }
        .navigationTitle("Weather")
        .task { await model.load() }
    }
}
