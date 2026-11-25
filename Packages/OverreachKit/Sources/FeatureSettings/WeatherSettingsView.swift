import DesignSystem
import Foundation
import SettingsPresentation
import SwiftUI

public struct WeatherSettingsView: View {
    let model: WeatherSettingsModel
    @State private var key = ""
    @State private var onboarding: WeatherOnboardingModel?

    public init(model: WeatherSettingsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if model.canChooseProvider {
                providerPicker
            }
            Section {
                Text("Weather uses the approximate area and time of eligible outdoor runs.")
                ForEach(model.limitations) { limitation in
                    LabeledContent {
                        Text(verbatim: limitation.detail).multilineTextAlignment(.trailing)
                    } label: {
                        Text(verbatim: limitation.title)
                    }
                }
            } header: {
                Text("What to expect")
            }
            if model.showsKeySection {
                keySection
            } else {
                openMeteoSection
            }
            if let url = model.attributionURL {
                Section {
                    Link(destination: url) { Text(verbatim: model.attributionTitle) }
                }
            }
        }
        .navigationTitle("Weather")
        .task { await model.load() }
        .sheet(
            item: $onboarding,
            onDismiss: { Task { await model.load() } },
            content: { onboarding in WeatherOnboardingView(model: onboarding) }
        )
    }

    private var providerPicker: some View {
        Section {
            ForEach(model.providerOptions) { option in
                Button {
                    Task { await model.selectProvider(option.provider) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            Text(verbatim: option.title).foregroundStyle(.primary)
                            Text(verbatim: option.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.isSelected {
                            Image(systemName: "checkmark").foregroundStyle(StatusTone.positive.color)
                        }
                    }
                }
                .accessibilityAddTraits(option.isSelected ? .isSelected : [])
            }
        } header: {
            Text("Provider")
        } footer: {
            Text("Switching provider clears the saved forecast. A saved OpenWeather key stays until you disconnect.")
        }
    }

    @ViewBuilder private var openMeteoSection: some View {
        Section {
            if model.needsOpenMeteoConfirmation {
                Button {
                    onboarding = model.makeOnboarding()
                } label: {
                    Label("Use Open-Meteo", systemImage: "checkmark.shield")
                }
            } else {
                Label("Open-Meteo is connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(StatusTone.positive.color)
            }
        }
    }

    @ViewBuilder private var keySection: some View {
        Section {
            if model.provider == .openWeatherOneCall {
                Text("Set your OpenWeather One Call daily limit to 1,000 or fewer to avoid charges.")
            }
            if let note = model.modeNote {
                Text(verbatim: note).foregroundStyle(.secondary)
            }
            if model.showsKeyField {
                if model.connection == .disconnected {
                    Button {
                        onboarding = model.makeOnboarding()
                    } label: {
                        Label("Set up with a guide", systemImage: "list.number")
                    }
                }
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
