import DesignSystem
import Domain
import SettingsPresentation
import SwiftUI

public struct TrainingProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: TrainingProfileModel
    private let onSave: () -> Void

    public init(model: TrainingProfileModel, onSave: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            if let message = model.errorMessage {
                Section {
                    InlineNotice(
                        Text(message), tone: .critical,
                        retry: model.isLoaded ? nil : { Task { await model.load() } }
                    )
                }
            }
            if model.isLoaded {
                goalSection
                aboutSection
                walkingSection
                devicesSection
            } else if model.errorMessage == nil {
                ProgressView()
            }
        }
        .disabled(model.isSaving)
        .navigationTitle("Training profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(model.isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!model.canSave)
            }
        }
        .task { await model.load() }
    }

    private var goalSection: some View {
        @Bindable var model = model
        return Section {
            Picker("Goal", selection: $model.goalKind) {
                if model.goalKind == nil {
                    Text("None").tag(TrainingGoal.Kind?.none)
                }
                ForEach(model.goalOptions) { option in
                    Text(option.name).tag(TrainingGoal.Kind?.some(option.value))
                }
            }
        } footer: {
            Text("Plan advice is judged against this goal. You can change it in Plan.")
        }
    }

    private var aboutSection: some View {
        @Bindable var model = model
        return Section {
            Picker("Sex", selection: $model.sex) {
                Text("Not provided").tag(BiologicalSex?.none)
                ForEach(model.sexOptions) { option in
                    Text(option.name).tag(BiologicalSex?.some(option.value))
                }
            }
            if model.showsCycleTracking {
                Picker("Cycle tracking", selection: $model.cycleTracking) {
                    ForEach(model.cycleOptions) { option in
                        Text(option.name).tag(option.value)
                    }
                }
            }
        } header: {
            Text("About you")
        } footer: {
            Text("Optional. It is only used as training context.")
        }
    }

    private var walkingSection: some View {
        @Bindable var model = model
        return Section {
            Toggle("I walk a dog", isOn: $model.walkingRoutine.hasDog)
            if model.walkingRoutine.hasDog {
                TextField("Dog's name", text: $model.dogName)
            }
            Picker("Usual walks per day", selection: $model.walkingRoutine.usualWalksPerDay) {
                Text("Not sure").tag(Int?.none)
                ForEach(model.walkOptions, id: \.self) { count in
                    Text(count.formatted()).tag(Int?.some(count))
                }
            }
            if model.showsWalkDetails {
                Toggle("These walks can't be skipped", isOn: $model.walkingRoutine.walksAreFixed)
                Toggle("I can jog during them", isOn: $model.walkingRoutine.canRunDuringWalks)
            }
        } header: {
            Text("Walking")
        } footer: {
            Text("Advice adapts to your walks and never removes the ones you can't skip.")
        }
    }

    private var devicesSection: some View {
        Section {
            device("Apple Watch", wearable: .appleWatch)
            device("Garmin", wearable: .garmin)
            device("Another watch or ring", wearable: .otherWatch)
        } header: {
            Text("Your devices")
        } footer: {
            Text("Pick all that apply. The app only shows what your devices measure.")
        }
    }

    private func device(_ title: LocalizedStringKey, wearable: Wearable) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.isSelected(wearable) },
            set: { model.setWearable(wearable, isSelected: $0) }
        ))
    }

    private func save() {
        Task {
            if await model.save() {
                dismiss()
                onSave()
            }
        }
    }
}
