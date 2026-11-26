import DesignSystem
import Domain
import ExercisesPresentation
import SwiftUI

// Views only: layout, styling and navigation. Defaults, limits and texts come from `ExercisesPresentation`
// (ADR-0014).

/// Holds the settings form for as long as the screen is shown.
struct ExerciseSettingsScreen: View {
    @State private var settings: ExerciseSettingsModel?

    init(editor: ExerciseEditorModel) {
        _settings = State(initialValue: editor.settingsEditor())
    }

    var body: some View {
        if let settings {
            ExerciseSettingsView(model: settings)
        } else {
            ContentUnavailableView("Exercise removed", systemImage: "trash")
        }
    }
}

/// Scheme, load increment, focus and main-lift flag of one exercise.
struct ExerciseSettingsView: View {
    @Bindable var model: ExerciseSettingsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let message = model.errorMessage {
                InlineNotice(Text(message), tone: .critical)
            }
            Section {
                Picker("Focus", selection: $model.focus) {
                    Text("Auto").tag(TrainingFocus?.none)
                    ForEach(model.focusOptions) { option in
                        Text(option.name).tag(TrainingFocus?.some(option.value))
                    }
                }
                Toggle("Main lift", isOn: $model.isMainLift)
            } footer: {
                Text("Main lifts weigh more in deload decisions.")
            }
            schemeSection
            Section {
                Picker("Load increment", selection: $model.incrementKg) {
                    ForEach(model.incrementOptions) { option in
                        Text(option.name).tag(option.value)
                    }
                }
            } footer: {
                Text("The smallest jump you can make with this exercise.")
            }
            Section {
                Text(model.suggestionLine).font(.footnote).foregroundStyle(.secondary)
                Button("Use defaults") { model.useDefaults() }
                    .disabled(!model.canUseDefaults)
            }
        }
        .navigationTitle(model.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { if await model.save() { dismiss() } }
                }
                .disabled(!model.canSave)
            }
        }
        .task { await model.load() }
    }

    private var schemeSection: some View {
        Section {
            Picker("Scheme", selection: $model.schemeKind) {
                ForEach(model.schemeOptions) { option in
                    Text(option.name).tag(option.value)
                }
            }
            Stepper("Sets: \(model.sets)", value: $model.sets, in: model.setsBounds)
            if model.showsRepRange {
                Stepper("Minimum reps: \(model.minReps)", value: $model.minReps, in: model.minRepsBounds)
                Stepper("Maximum reps: \(model.maxReps)", value: $model.maxReps, in: model.maxRepsBounds)
            }
            if model.showsReps {
                Stepper("Reps: \(model.reps)", value: $model.reps, in: model.repsBounds)
            }
            if model.showsRepBlocks {
                TextField("Rep blocks", text: $model.repBlocksText)
                if let message = model.repBlocksMessage {
                    InlineNotice(Text(message), tone: .critical)
                }
            }
            Picker("Target RPE", selection: $model.targetRPE) {
                ForEach(model.rpeOptions) { option in
                    Text(option.name).tag(option.value)
                }
            }
        } header: {
            Text("Progression")
        } footer: {
            Text(model.schemeExplanation)
        }
    }
}
