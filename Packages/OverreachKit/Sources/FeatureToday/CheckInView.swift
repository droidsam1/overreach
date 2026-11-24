import DesignSystem
import SwiftUI
import TodayPresentation

/// The daily check-in: sick, energy, soreness and a note. Renders `CheckInModel`; `onSaved` reloads Today.
struct CheckInView: View {
    @Bindable var model: CheckInModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let question = model.contextQuestionTitle {
                    Section {
                        Picker(selection: $model.contextAnswer) {
                            ForEach(model.contextOptions) { option in
                                Text(option.name).tag(Optional(option.value))
                            }
                        } label: {
                            Text(question)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text(question)
                    }
                }

                Section {
                    Toggle("I'm sick", isOn: $model.isSick)
                    Toggle(
                        "Chest discomfort, unusual breathlessness or dizziness", isOn: $model.hasExerciseWarningSigns
                    )
                } footer: {
                    Text("Mark sick if you have a fever or feel ill today.")
                }

                if let question = model.legResponseQuestionTitle {
                    Section {
                        Picker(selection: $model.legResponse) {
                            ForEach(model.legResponseOptions) { option in
                                Text(option.name).tag(Optional(option.value))
                            }
                        } label: {
                            Text(question)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text(question)
                    }
                }

                Section("Energy") {
                    Picker("Energy", selection: $model.energy) {
                        ForEach(model.energyOptions) { option in
                            Text(option.name).tag(Optional(option.value))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Muscle soreness") {
                    Picker("Muscle soreness", selection: $model.soreness) {
                        ForEach(model.sorenessOptions) { option in
                            Text(option.name).tag(Optional(option.value))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Note") {
                    TextField("Anything worth remembering", text: $model.note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Check-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
    }
}
