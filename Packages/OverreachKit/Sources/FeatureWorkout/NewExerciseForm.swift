import DesignSystem
import Domain
import PresentationKit
import SwiftUI

// Views only: what to prefill and when the form can be saved come from `NewExerciseModel` (ADR-0014).

/// Creates an exercise the picker did not find, pushed inside the picker. Most fields come prefilled from the
/// name, so the usual case is checking the muscles and tapping Add.
struct NewExerciseForm: View {
    @State private var model: NewExerciseModel
    private let onCreated: (Exercise) -> Void
    private let onUseExisting: (UUID) -> Void
    private let finish: () -> Void
    @FocusState private var isNameFocused: Bool

    /// - Parameters:
    ///   - onCreated: adds the saved exercise to the session or routine.
    ///   - onUseExisting: picks an exercise that already has the typed name.
    ///   - finish: closes the picker.
    init(
        model: NewExerciseModel,
        onCreated: @escaping (Exercise) -> Void,
        onUseExisting: @escaping (UUID) -> Void,
        finish: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onCreated = onCreated
        self.onUseExisting = onUseExisting
        self.finish = finish
    }

    var body: some View {
        Form {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            Section {
                TextField("Name", text: $model.name)
                    .accessibilityLabel(Text("Exercise name"))
                    .focused($isNameFocused)
                    .submitLabel(.done)
                if let existing = model.existing, let existingNotice = model.existingNotice {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        Text(existingNotice.message).font(.footnote).foregroundStyle(.secondary)
                        Button(existingNotice.useLabel) {
                            onUseExisting(existing.id)
                            finish()
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Picker("Equipment", selection: $model.equipment) {
                    ForEach(model.equipmentOptions) { option in
                        Text(option.name).tag(option.value)
                    }
                }
            }
            Section {
                ForEach(model.muscleOptions) { muscle in
                    Picker(muscle.name, selection: Binding(
                        get: { model.role(of: muscle.value) },
                        set: { model.setRole($0, for: muscle.value) }
                    )) {
                        ForEach(model.roleOptions) { role in
                            Text(role.name).tag(role.value)
                        }
                    }
                    .foregroundStyle(model.role(of: muscle.value) == .none ? Color.secondary : Color.primary)
                }
            } header: {
                Text("Muscles")
            } footer: {
                Text(model.musclesNote)
            }
        }
        .navigationTitle("New exercise")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    Task {
                        guard let exercise = await model.save() else { return }
                        onCreated(exercise)
                        finish()
                    }
                }
                .disabled(!model.canSave)
            }
        }
        .onAppear { if model.name.isEmpty { isNameFocused = true } }
    }
}
