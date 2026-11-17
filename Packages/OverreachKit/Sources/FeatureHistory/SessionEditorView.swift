import DesignSystem
import Domain
import SwiftUI

/// Sheet to correct a past session. Reuses the logger's set fields (`SetValueFields`).
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
                if !model.issues.isEmpty || model.errorMessage != nil {
                    Section {
                        if let message = model.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }
                        ForEach(model.issues, id: \.self) { issue in
                            Label(issue.message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
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
                ExercisePicker(exercises: model.catalog) { model.addExercise($0) }
            }
            .sheet(item: $replacing) { target in
                ExercisePicker(title: "Replace exercise", exercises: model.catalog) { exercise in
                    model.replaceExercise(of: target.id, with: exercise)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
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
                Button("Add end time", systemImage: "clock") {
                    model.setEnd(model.draft.startedAt.addingTimeInterval(3_600))
                }
            }
            Picker("Focus", selection: $model.draft.focus) {
                Text("Auto").tag(TrainingFocus?.none)
                ForEach(TrainingFocus.allCases, id: \.self) { focus in
                    Text(focus.title).tag(TrainingFocus?.some(focus))
                }
            }
            TextField("Notes", text: notes, axis: .vertical)
                .lineLimit(1...5)
        }
    }

    private var notes: Binding<String> {
        Binding(get: { model.draft.notes ?? "" }, set: { model.draft.notes = $0 })
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
                HStack(spacing: Spacing.small) {
                    SetNumberLabel((entry.sets.firstIndex { $0.id == set.id } ?? 0) + 1)
                    SetValueFields(weightKg: $set.weightKg, reps: $set.reps, rpe: $set.rpe)
                    Menu {
                        Picker("Set type", selection: $set.kind) {
                            ForEach(SetKind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
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
                        .disabled(model.draft.entries.first?.id == entry.id)
                    Button("Move down", systemImage: "arrow.down") { model.moveExercise(entry.id, by: 1) }
                        .disabled(model.draft.entries.last?.id == entry.id)
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

extension SessionEditIssue {
    var message: LocalizedStringKey {
        switch self {
        case .missingName: "Give the session a name."
        case .noSets: "Add at least one set, or delete the session from History."
        case .endsBeforeStart: "The end time is before the start time."
        case .invalidValues: "Weights and reps can't be negative, and RPE goes from 1 to 10."
        }
    }
}
