import Domain
import PlanPresentation
import SwiftUI

struct RunningCalendarEntryView: View {
    let model: PlanModel
    @State var draft: RunningCalendarDraft
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [RunningCompletionChoice] = []
    @State private var confirmRemoval = false

    init(model: PlanModel, draft: RunningCalendarDraft) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                Section {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .disabled(draft.completion != nil)
                    Picker("Session type", selection: $draft.purpose) {
                        ForEach(model.runningSessionOptions) { option in Text(option.name).tag(option.value) }
                    }
                    if draft.showsWorkoutDetails {
                        TextField("Planned minutes (0 if unknown)", value: $draft.minutes, format: .number)
                        TextField("Planned distance in km (0 if unknown)", value: $draft.distanceKm, format: .number)
                    }
                }
                if draft.showsCompletion && !choices.isEmpty {
                    Section {
                        Picker("Recorded run", selection: $draft.completion) {
                            Text("Unlinked").tag(nil as PlannedRunCompletion?)
                            ForEach(choices) { choice in Text(choice.title).tag(Optional(choice.completion)) }
                        }
                    } footer: {
                        Text("To move a completed entry, unlink the recorded run first.")
                    }
                }
                if !draft.isNew {
                    Button("Remove running day", role: .destructive) { confirmRemoval = true }
                        .disabled(model.isSavingProfile)
                }
            }
            .navigationTitle("Running day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await model.saveRunningEntry(draft) { dismiss() } } }
                        .disabled(!draft.canSave || model.isSavingProfile)
                }
            }
            .confirmationDialog("Remove this planned day?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove running day", role: .destructive) {
                    Task { if await model.removeRunningEntry(draft.id) { dismiss() } }
                }
            }
            .task(id: draft.date) {
                choices = []
                let available = await model.runningCompletionChoices(for: draft)
                if !Task.isCancelled { choices = available }
            }
        }
    }
}
