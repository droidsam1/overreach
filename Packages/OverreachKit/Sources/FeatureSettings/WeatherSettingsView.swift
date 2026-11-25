import DesignSystem
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
                if model.showsKeyField {
                    keyEntry
                } else {
                    connected
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

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder private var keyEntry: some View {
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
        .disabled(trimmedKey.isEmpty || model.isSaving)
        if model.canCancelReplacing {
            Button("Cancel") {
                key = ""
                model.cancelReplacing()
            }
            .disabled(model.isSaving)
        }
    }

    @ViewBuilder private var connected: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text("API key saved")
                Text(verbatim: WeatherSettingsModel.maskedKey).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(StatusTone.positive.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Connected"))
        .accessibilityValue(Text("API key saved"))
        Button("Replace key") { model.beginReplacing() }
            .disabled(model.isSaving)
        Button("Disconnect weather", role: .destructive) {
            Task { await model.disconnect() }
        }
        .disabled(model.isSaving)
    }
}
