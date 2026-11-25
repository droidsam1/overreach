import DesignSystem
import SettingsPresentation
import SwiftUI

/// Stepper sheet that explains how to get an OpenWeather key and saves it once OpenWeather accepts it.
struct WeatherOnboardingView: View {
    let model: WeatherOnboardingModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    ProgressView(value: model.progress) {
                        Text(verbatim: model.progressText).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(verbatim: model.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(verbatim: model.message)
                    stepAction
                    outcome
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.medium)
            }
            .navigationTitle("Weather setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.isConnected ? "Done" : "Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { navigation }
        }
    }

    @ViewBuilder private var stepAction: some View {
        switch model.action {
        case .none:
            EmptyView()
        case let .openLink(title, url):
            Link(destination: url) {
                Label {
                    Text(verbatim: title)
                } icon: {
                    Image(systemName: "safari")
                }
            }
            .buttonStyle(.bordered)
        case .pasteAndSave:
            keyEntry
        }
    }

    @ViewBuilder private var keyEntry: some View {
        @Bindable var model = model
        SecureField("OpenWeather API key", text: $model.key)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .disabled(model.isValidating || model.isConnected)
        HStack {
            PasteButton(payloadType: String.self) { strings in
                if let text = strings.first { model.paste(text) }
            }
            Button("Check and save") { Task { await model.submit() } }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSubmit)
        }
    }

    @ViewBuilder private var outcome: some View {
        switch model.outcome {
        case .idle:
            EmptyView()
        case .validating:
            ProgressView("Checking the key…")
        case .succeeded:
            Label {
                Text("Weather is connected.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(StatusTone.positive.color)
            }
            .accessibilityElement(children: .combine)
        case let .failed(message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(StatusTone.caution.color)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var navigation: some View {
        HStack {
            Button("Back") { model.back() }
                .disabled(!model.canGoBack)
            Spacer()
            if model.canGoNext {
                Button("Next") { model.next() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.medium)
        .background(.bar)
    }
}
