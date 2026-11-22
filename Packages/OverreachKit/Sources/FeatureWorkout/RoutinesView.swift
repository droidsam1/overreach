import DesignSystem
import Domain
import PresentationKit
import SwiftUI
import WorkoutPresentation

// Views only: layout, styling and navigation. Rules and texts come from `WorkoutPresentation` (ADR-0014).

/// What the Train tab shows when no session is open: start an empty session or one from a routine.
struct StartSessionView: View {
    let routines: RoutinesModel
    let notice: String?
    let onStartEmpty: () -> Void
    let onStart: (Routine) -> Void
    let onEdit: (UUID) -> Void

    var body: some View {
        List {
            if let notice {
                StatusLabel(title: notice, tone: .positive)
            }
            if let message = routines.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let next = routines.upNext {
                Section {
                    Button {
                        onStart(next.routine)
                    } label: {
                        HStack(spacing: Spacing.medium) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(next.title).font(.headline).foregroundStyle(.primary)
                                Text(next.detail).font(.subheadline).foregroundStyle(.secondary)
                                if let progress = next.weekProgress {
                                    Text(progress).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(next.exerciseList)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Starts this session")
                } header: {
                    Text("Up next in your plan")
                }
            }
            Section {
                Button("Start empty session", systemImage: "plus.circle.fill", action: onStartEmpty)
            } footer: {
                Text("Targets come from your history.")
            }
            if !routines.planChecks.isEmpty {
                Section("Plan check") {
                    ForEach(routines.planChecks) { check in
                        PlanCheckView(check: check) {
                            Task { await routines.accept(check) }
                        }
                    }
                }
            }
            Section {
                ForEach(routines.rows) { row in
                    routineRow(row)
                }
            } header: {
                Text("Routines")
            } footer: {
                if routines.showsEmptyHint {
                    Text("Create one with +, or save a past session as a routine from History.")
                }
            }
        }
        .refreshable { await routines.load() }
    }

    private func routineRow(_ row: RoutineRow) -> some View {
        HStack {
            Button {
                onStart(row.routine)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(row.name).font(.headline).foregroundStyle(.primary)
                    Text(row.exerciseList)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let focus = row.focus {
                        Text(focus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            Menu {
                Button("Edit", systemImage: "pencil") { onEdit(row.id) }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await routines.delete(row.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Routine options")
        }
    }
}

/// Name, focus and ordered exercises of a routine, presented as a sheet.
struct RoutineEditorView: View {
    @Bindable var model: RoutineEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingExercise = false

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
                Section {
                    TextField("Name", text: $model.name)
                    Picker("Focus", selection: $model.focus) {
                        Text("Auto").tag(TrainingFocus?.none)
                        ForEach(model.focusOptions) { option in
                            Text(option.name).tag(TrainingFocus?.some(option.value))
                        }
                    }
                }
                Section {
                    ForEach(model.exerciseRows) { row in
                        Text(row.name)
                    }
                    .onDelete { model.removeExercises(at: $0) }
                    .onMove { model.moveExercises(from: $0, to: $1) }
                    Button("Add exercise", systemImage: "plus.circle.fill") { isPickingExercise = true }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Weights and reps are suggested from your history when you start.")
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle(model.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await model.save() { dismiss() } }
                    }
                    .disabled(!model.canSave)
                }
            }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePicker(
                    items: model.exerciseChoices.map(PickerItem.init),
                    onPick: { model.addExercise(id: $0) },
                    createForm: { name, finish in
                        NewExerciseForm(
                            model: model.newExercise(named: name),
                            onCreated: { model.addCreated($0) },
                            onUseExisting: { model.addExercise(id: $0) },
                            finish: finish
                        )
                    }
                )
                .task { await model.reloadCatalog() }
            }
        }
    }
}

/// A proposed change to the plan: what, why (with the evidence level) and, when it changes the plan, a button.
private struct PlanCheckView: View {
    let check: PlanCheckRow
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label {
                Text(check.text).font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
            }
            Text(check.reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ReadingLinks(items: check.readings.map(ReadingLinkItem.init))
            if let action = check.actionTitle {
                Button(action, action: onAccept)
                    .buttonStyle(BrandButtonStyle())
            }
        }
        .padding(.vertical, Spacing.xSmall)
    }
}

extension ReadingLinkItem {
    /// The display values of a curated reading (ADR-0030).
    init(_ reading: Reading) {
        self.init(url: reading.url, title: reading.title, detail: reading.detail(), note: reading.note)
    }
}
