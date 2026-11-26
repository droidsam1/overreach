import DesignSystem
import Domain
import PresentationKit
import SwiftUI
import WorkoutPresentation

// Views only: layout, styling and navigation. Rules and texts come from `WorkoutPresentation` (ADR-0014).

/// What Train shows before a workout starts.
struct StartSessionView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let routines: RoutinesModel
    let notice: String?
    let onStartEmpty: () -> Void
    let onStart: (Routine) -> Void
    let onEdit: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                notices
                if let next = routines.upNext {
                    nextSession(next)
                }
                if emptySessionIsPrimary {
                    emptySession
                    routineCards
                } else {
                    routineCards
                    emptySession
                }
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await routines.load() }
    }

    @ViewBuilder private var notices: some View {
        if notice != nil || routines.errorMessage != nil {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if let notice {
                    StatusLabel(title: notice, tone: .positive)
                }
                if let message = routines.errorMessage {
                    InlineNotice(
                        Text(verbatim: message), tone: .critical,
                        retry: routines.canRetryLoad ? { Task { await routines.load() } } : nil
                    )
                }
            }
        }
    }

    private func nextSession(_ next: UpNextRow) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                AdaptiveStack(verticalAlignment: .top, spacing: Spacing.medium) {
                    IconTile(symbolName: "calendar.badge.clock", color: .accentColor)
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text("Up next in your plan").font(.subheadline).foregroundStyle(.secondary)
                        SectionHeader(Text(verbatim: next.title), font: .title2.weight(.bold))
                        Text(next.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let progress = next.weekProgress {
                    Text(progress).font(.subheadline.monospacedDigit())
                }
                if !next.exerciseList.isEmpty {
                    Text(next.exerciseList).font(.subheadline).foregroundStyle(.secondary)
                }
                Button { onStart(next.routine) } label: {
                    Label("Start workout", systemImage: "play.fill")
                }
                .buttonStyle(BrandButtonStyle())
            }
        }
    }

    @ViewBuilder private var routineCards: some View {
        if !routines.routines.isEmpty || !routines.planChecks.isEmpty || routines.showsEmptyHint {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SectionHeader(Text("Routines"), font: .title3.weight(.semibold))
                ForEach(routines.rows) { row in
                    routineCard(row)
                }
                if routines.showsEmptyHint {
                    Text("Create one with +, or save a past session as a routine from History.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !routines.planChecks.isEmpty {
                    Card {
                        DisclosureGroup("Plan check") {
                            VStack(alignment: .leading, spacing: Spacing.medium) {
                                ForEach(routines.planChecks) { check in
                                    PlanCheckView(check: check) {
                                        Task { await routines.accept(check) }
                                    }
                                }
                            }
                            .padding(.top, Spacing.small)
                        }
                    }
                }
            }
        }
    }

    private func routineCard(_ row: RoutineRow) -> some View {
        Card {
            AdaptiveStack {
                Button {
                    onStart(row.routine)
                } label: {
                    AdaptiveStack(verticalAlignment: .top, spacing: Spacing.small) {
                        IconTile(symbolName: "play.fill", color: .accentColor)
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            Text(row.name).font(.headline).foregroundStyle(.primary)
                            if !row.exerciseList.isEmpty {
                                Text(row.exerciseList)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            }
                            if let focus = row.focus {
                                Text(focus).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Starts this session")
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
                .accessibilityLabel("Routine options")
            }
        }
    }

    private var emptySessionIsPrimary: Bool {
        routines.upNext == nil && routines.routines.isEmpty
    }

    private var emptySession: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            if emptySessionIsPrimary {
                Button(action: onStartEmpty) {
                    Label("Start empty session", systemImage: "plus.circle.fill")
                }
                .buttonStyle(BrandButtonStyle())
            } else {
                Button(action: onStartEmpty) {
                    Label("Start empty session", systemImage: "plus.circle.fill")
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
            Text("Targets come from your history.").font(.footnote).foregroundStyle(.secondary)
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
                    InlineNotice(Text(message), tone: .critical)
                }
                Section {
                    TextField("Name", text: $model.name)
                        .accessibilityLabel(Text("Routine name"))
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
            InlineNotice(Text(check.text), tone: .caution)
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
