import DesignSystem
import Domain
import HistoryPresentation
import PresentationKit
import SwiftUI

/// Sheet to correct a past session. Reuses the logger's set fields (`SetValueFields`).
/// Views only (ADR-0014): validation, options and edits live in `SessionEditorModel`.
struct SessionEditorView: View {
    @State private var model: SessionEditorModel
    let onSaved: (StrengthSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingExercise = false
    @State private var replacing: ReplaceTarget?
    @State private var isConfirmingDiscard = false

    init(model: SessionEditorModel, onSaved: @escaping (StrengthSession) -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                SessionFields(model: model)
                if !model.issueMessages.isEmpty || model.errorMessage != nil {
                    Section {
                        if let message = model.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }
                        ForEach(model.issueMessages, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                    }
                }
                ForEach($model.draft.entries) { $entry in
                    EntrySection(
                        model: model,
                        entry: $entry,
                        onReplace: { replacing = ReplaceTarget(id: entry.id) }
                    )
                }
                Section {
                    Button("Add exercise", systemImage: "plus.circle.fill") { isAddingExercise = true }
                } footer: {
                    Text("Empty sets and exercises without sets are removed when you save.")
                }
            }
            .navigationTitle("Edit session")
            .toolbar { toolbar }
            .interactiveDismissDisabled(model.hasChanges)
            .sheet(isPresented: $isAddingExercise) {
                ExercisePicker(items: pickerItems) { model.addExercise(id: $0) }
            }
            .sheet(item: $replacing) { target in
                ExercisePicker(title: "Replace exercise", items: pickerItems) { id in
                    model.replaceExercise(of: target.id, withID: id)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
    }

    private var pickerItems: [PickerItem] {
        model.exerciseChoices.map { PickerItem(id: $0.id, title: $0.name, searchTerms: $0.searchTerms) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if model.hasChanges { isConfirmingDiscard = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task {
                    if let saved = await model.save() {
                        onSaved(saved)
                        dismiss()
                    }
                }
            }
            .disabled(!model.canSave)
        }
    }
}

/// The exercise entry whose exercise is being replaced.
private struct ReplaceTarget: Identifiable {
    let id: ExerciseEntry.ID
}

/// Name, times, focus and notes.
private struct SessionFields: View {
    @Bindable var model: SessionEditorModel

    var body: some View {
        Section("Session") {
            TextField("Name", text: $model.draft.name)
            DatePicker(
                "Start",
                selection: Binding(get: { model.draft.startedAt }, set: { model.moveStart(to: $0) })
            )
            if let endedAt = model.draft.endedAt {
                DatePicker("End", selection: Binding(get: { endedAt }, set: { model.setEnd($0) }))
                    .swipeActions {
                        Button("Remove end time", role: .destructive) { model.setEnd(nil) }
                    }
            } else {
                Button("Add end time", systemImage: "clock") { model.addEndTime() }
            }
            Picker("Focus", selection: $model.draft.focus) {
                Text("Auto").tag(TrainingFocus?.none)
                ForEach(model.focusOptions) { option in
                    Text(option.name).tag(TrainingFocus?.some(option.value))
                }
            }
            TextField("Notes", text: $model.notesText, axis: .vertical)
                .lineLimit(1...5)
        }
    }
}

/// One exercise with its editable sets.
private struct EntrySection: View {
    let model: SessionEditorModel
    @Binding var entry: ExerciseEntry
    let onReplace: () -> Void

    var body: some View {
        Section {
            ForEach($entry.sets) { $set in
                AdaptiveStack(spacing: Spacing.small) {
                    SetNumberLabel(model.number(of: set.id, in: entry.id))
                    SetValueFields(weightKg: $set.weightKg, reps: $set.reps, rpe: $set.rpe)
                    Menu {
                        Picker("Set type", selection: $set.kind) {
                            ForEach(model.setKindOptions) { option in
                                Text(option.name).tag(option.value)
                            }
                        }
                    } label: {
                        Text(set.kind.badge ?? "–")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 20)
                    }
                    .accessibilityLabel("Set type")
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { model.removeSet(set.id, from: entry.id) }
                }
            }
            Button("Add set", systemImage: "plus") { model.addSet(to: entry.id) }
        } header: {
            HStack {
                Text(model.name(of: entry.exerciseID))
                Spacer()
                Menu {
                    Button("Replace exercise", systemImage: "arrow.left.arrow.right", action: onReplace)
                    Button("Move up", systemImage: "arrow.up") { model.moveExercise(entry.id, by: -1) }
                        .disabled(!model.canMoveUp(entry.id))
                    Button("Move down", systemImage: "arrow.down") { model.moveExercise(entry.id, by: 1) }
                        .disabled(!model.canMoveDown(entry.id))
                    Button("Remove exercise", systemImage: "trash", role: .destructive) {
                        model.removeExercise(entry.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Exercise options")
            }
        }
    }
}
