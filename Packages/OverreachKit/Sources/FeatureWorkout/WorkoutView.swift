import DesignSystem
import Domain
import PresentationKit
import SwiftUI
import WorkoutPresentation

// Views only: layout, styling and navigation. Targets, texts and decisions come from `WorkoutPresentation`
// (ADR-0014), so this file can be redesigned freely.

/// The Train tab: start a session, empty or from a routine, and log it.
public struct WorkoutView: View {
    @State private var model: WorkoutModel
    @State private var routines: RoutinesModel
    @State private var routineEditor: RoutineEditorModel?
    @State private var isPickingExercise = false
    @State private var isConfirmingDiscard = false

    public init(model: WorkoutModel, routines: RoutinesModel) {
        _model = State(initialValue: model)
        _routines = State(initialValue: routines)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.isSessionActive {
                    SessionList(model: model, isPickingExercise: $isPickingExercise)
                } else {
                    StartSessionView(
                        routines: routines,
                        onStartEmpty: { model.start() },
                        onStart: { routine in Task { await model.start(routine) } },
                        onEdit: { routineEditor = routines.editor(for: $0) }
                    )
                }
            }
            .navigationTitle(model.isSessionActive ? model.sessionName : String(localized: "Train"))
            .inlineTitle(model.isSessionActive)
            .toolbar { toolbar }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePicker(items: model.exerciseChoices.map(PickerItem.init)) { id in
                    Task { await model.add(exerciseID: id) }
                }
                // Exercises may have been created since this screen first appeared.
                .task { await model.load() }
            }
            .sheet(item: $routineEditor) { editor in
                RoutineEditorView(model: editor)
            }
            .confirmationDialog("Discard this session?", isPresented: $isConfirmingDiscard) {
                Button("Discard", role: .destructive) { model.discard() }
            }
            .task {
                await model.load()
                await routines.load()
            }
            // Progression settings and routines may have changed in another tab (e.g. imported from an AI).
            .onAppear {
                Task {
                    await model.applySettingsChanges()
                    await routines.load()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.isSessionActive {
            // Long routine names wrap instead of being cut between the Discard and Finish buttons.
            ToolbarItem(placement: .principal) {
                Text(model.sessionName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", role: .destructive) { isConfirmingDiscard = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish") { Task { await model.finish() } }
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button("New routine", systemImage: "plus") { routineEditor = routines.newEditor() }
            }
        }
    }
}

/// The exercises and sets of the session in progress, bound directly to the model.
private struct SessionList: View {
    @Bindable var model: WorkoutModel
    @Binding var isPickingExercise: Bool
    @State private var isShowingGuide = false

    var body: some View {
        List {
            Button("How to log sets", systemImage: "questionmark.circle") { isShowingGuide = true }
            Picker("Session focus", selection: Binding(
                get: { model.sessionFocus },
                set: { focus in Task { await model.setSessionFocus(focus) } }
            )) {
                Text("Auto").tag(TrainingFocus?.none)
                ForEach(model.focusOptions) { option in
                    Text(option.name).tag(TrainingFocus?.some(option.value))
                }
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            ForEach($model.exercises) { $exercise in
                Section {
                    TargetSummaryView(summary: exercise.summary)
                    ForEach($exercise.sets) { $set in
                        SetRow(number: exercise.number(of: set.id), set: $set) { isDone in
                            model.setDone(isDone, set: set.id, in: exercise.id)
                        }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    model.removeSet(set.id, from: exercise.id)
                                }
                            }
                    }
                    Button("Add set", systemImage: "plus") { model.addSet(to: exercise.id) }
                    TextField("Notes", text: $exercise.notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    HStack {
                        Text(exercise.name)
                        Spacer()
                        Menu {
                            Picker("Exercise focus", selection: Binding(
                                get: { exercise.declaredFocus },
                                set: { focus in Task { await model.setFocus(focus, of: exercise.id) } }
                            )) {
                                Text("Same as the session").tag(TrainingFocus?.none)
                                ForEach(model.focusOptions) { option in
                                    Text(option.name).tag(TrainingFocus?.some(option.value))
                                }
                            }
                            .pickerStyle(.menu)
                            Button("Remove exercise", systemImage: "trash", role: .destructive) {
                                model.removeExercise(exercise.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Exercise options")
                    }
                }
            }
            if model.exercises.isEmpty {
                Text("Add an exercise to see its target from your history.").foregroundStyle(.secondary)
            }
            Button("Add exercise", systemImage: "plus.circle.fill") { isPickingExercise = true }
            Section("Session notes") {
                TextField("How did it go? Sleep, energy, anything worth remembering.", text: $model.sessionNotes,
                          axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .sheet(isPresented: $isShowingGuide) { SetLoggingGuide() }
        .keyboardDoneButton()
        .safeAreaInset(edge: .bottom) {
            if model.rest.isActive {
                RestTimerView(model: model.rest)
            }
        }
    }
}

/// The engine's target and status for one exercise, with reasons and their evidence level.
private struct TargetSummaryView: View {
    let summary: TargetSummary

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(Array(summary.reasons.enumerated()), id: \.offset) { Text($0.element) }
                if !summary.stallSuggestions.isEmpty {
                    Text("Stalled — try, in order:").bold()
                    ForEach(Array(summary.stallSuggestions.enumerated()), id: \.offset) { Text($0.element) }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                AdaptiveStack {
                    Text(summary.targetLine).font(.subheadline.monospacedDigit())
                    Spacer()
                    if let status = summary.status {
                        Text(status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(summary.isStalled ? .orange : .secondary)
                    }
                }
                Text(summary.focusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetRow: View {
    let number: Int
    @Binding var set: DraftSet
    let onDoneChange: (Bool) -> Void

    var body: some View {
        AdaptiveStack(spacing: Spacing.small) {
            SetNumberLabel(number)
            SetValueFields(weightKg: $set.weightKg, reps: $set.reps, rpe: $set.rpe)
            Toggle(isOn: Binding(get: { set.isDone }, set: onDoneChange)) {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Set \(number) done")
        }
        .opacity(set.isDone ? 0.6 : 1)
    }
}

extension View {
    /// Inline title on iOS while `isInline`, so the session name sits between the toolbar buttons.
    @ViewBuilder
    fileprivate func inlineTitle(_ isInline: Bool) -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(isInline ? .inline : .automatic)
        #else
        self
        #endif
    }
}

extension PickerItem {
    init(_ choice: ExerciseChoice) {
        self.init(id: choice.id, title: choice.name, searchTerms: choice.searchTerms)
    }
}
