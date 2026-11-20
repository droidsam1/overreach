import DesignSystem
import ExercisesPresentation
import SwiftUI

// Views only: layout, styling and navigation. Every decision, filter and text derived from rules comes from
// `ExercisesPresentation` (ADR-0014), so this file can be redesigned freely.

/// Exercise list: create exercises (issue #17), assign muscles to imported ones and merge duplicates (issue #13).
/// Pushed inside the caller's navigation stack.
public struct ExercisesView: View {
    @State private var model: ExercisesModel
    @State private var isCreating = false

    public init(model: ExercisesModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        List {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            if !model.needsMappingRows.isEmpty {
                Section {
                    ForEach(model.needsMappingRows) { row in
                        ExerciseRowLink(model: model, row: row)
                    }
                } header: {
                    Text("Needs muscles")
                } footer: {
                    Text("""
                        Imported exercises that are not in the catalog. Their volume does not count until you assign \
                        their muscles or merge them into a catalog exercise.
                        """)
                }
            }
            Section("All exercises") {
                ForEach(model.allRows) { row in
                    ExerciseRowLink(model: model, row: row)
                }
            }
        }
        .navigationTitle("Exercises")
        .searchable(text: $model.searchText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New exercise", systemImage: "plus") { isCreating = true }
            }
        }
        .sheet(isPresented: $isCreating) {
            NavigationStack { NewExerciseScreen(list: model) }
        }
        .overlay {
            if model.showsLoadingIndicator {
                ProgressView()
            } else if model.showsNoResults {
                ListEmptyState(query: model.searchText, title: "No exercises", systemImage: "dumbbell")
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

private struct ExerciseRowLink: View {
    let model: ExercisesModel
    let row: ExerciseRow

    var body: some View {
        NavigationLink {
            EditorScreen(list: model, exerciseID: row.id)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(row.name)
                Group {
                    if row.needsMuscles {
                        Label("No muscles assigned", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    } else {
                        Text(row.muscles)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .badge(row.sessionCount)
    }
}

/// Holds the editor for as long as the screen is shown, so the draft survives re-renders of the list.
private struct EditorScreen: View {
    @State private var editor: ExerciseEditorModel?

    init(list: ExercisesModel, exerciseID: UUID) {
        _editor = State(initialValue: list.editor(for: exerciseID))
    }

    var body: some View {
        if let editor {
            ExerciseEditorView(model: editor)
        } else {
            ContentUnavailableView("Exercise removed", systemImage: "trash")
        }
    }
}

/// The form to create an exercise, presented as a sheet.
private struct NewExerciseScreen: View {
    @State private var editor: ExerciseEditorModel
    @Environment(\.dismiss) private var dismiss

    init(list: ExercisesModel) {
        _editor = State(initialValue: list.newExerciseEditor())
    }

    var body: some View {
        ExerciseEditorView(model: editor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
    }
}

/// Create or edit an exercise: names, muscles and equipment, copy them from a similar exercise, or merge it.
struct ExerciseEditorView: View {
    @Bindable var model: ExerciseEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if model.exists {
            form
        } else {
            ContentUnavailableView("Exercise removed", systemImage: "trash")
        }
    }

    private var form: some View {
        Form {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            if model.canEditNames {
                namesSection
            }
            if !model.suggestions.isEmpty {
                Section {
                    ForEach(model.suggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                } header: {
                    Text("Similar exercises")
                } footer: {
                    Text("Copy fills in the muscles below. Merge moves this exercise's history to the other one.")
                }
            }
            Section {
                Picker("Equipment", selection: $model.draft.equipment) {
                    ForEach(model.equipmentOptions) { option in
                        Text(option.name).tag(option.value)
                    }
                }
            }
            Section {
                ForEach(model.muscleOptions) { option in
                    Toggle(option.name, isOn: Binding(
                        get: { model.isPrimary(option.value) },
                        set: { model.setPrimary(option.value, $0) }
                    ))
                }
            } header: {
                Text("Primary muscles")
            } footer: {
                Text("Each working set counts as one set for these muscles.")
            }
            Section {
                ForEach(model.muscleOptions) { option in
                    Toggle(option.name, isOn: Binding(
                        get: { model.isSecondary(option.value) },
                        set: { model.setSecondary(option.value, $0) }
                    ))
                }
            } header: {
                Text("Secondary muscles")
            } footer: {
                Text("Each working set counts as half a set for these muscles.")
            }
            if model.canEditSettings {
                Section {
                    NavigationLink("Progression settings") {
                        ExerciseSettingsScreen(editor: model)
                    }
                }
            }
            if model.canMerge {
                Section {
                    NavigationLink("Merge into another exercise…") {
                        MergeTargetList(model: model)
                    }
                }
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
        .confirmationDialog(
            "Merge exercises?",
            isPresented: Binding(get: { model.pendingMerge != nil }, set: { if !$0 { model.cancelMerge() } }),
            titleVisibility: .visible,
            presenting: model.pendingMerge
        ) { confirmation in
            Button(confirmation.confirmLabel) {
                Task { if await model.confirmMerge() { dismiss() } }
            }
            Button("Cancel", role: .cancel) { model.cancelMerge() }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var namesSection: some View {
        Section {
            TextField("Name", text: $model.name)
            TextField("Other names", text: $model.aliasesText)
            if let message = model.nameMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("Separate other names with commas. Search and imports use them too.")
        }
    }

    private func suggestionRow(_ suggestion: SuggestionRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(suggestion.name)
            Text(suggestion.muscles)
                .font(.footnote)
                .foregroundStyle(.secondary)
            AdaptiveStack(spacing: Spacing.small) {
                Button("Copy muscles") { model.copyMuscles(from: suggestion.id) }
                if model.canMerge {
                    Spacer()
                    Button("Merge") { model.requestMerge(into: suggestion.id) }
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }
}

/// Every mapped exercise, searchable, to pick a merge target.
private struct MergeTargetList: View {
    @Bindable var model: ExerciseEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(model.mergeTargets) { target in
            Button {
                model.requestMerge(into: target.id)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(target.name).foregroundStyle(.primary)
                    Text(target.muscles).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if model.mergeTargets.isEmpty {
                ListEmptyState(query: model.mergeSearchText, title: "No other exercises", systemImage: "dumbbell")
            }
        }
        .navigationTitle("Merge into")
        .searchable(text: $model.mergeSearchText)
    }
}
