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
    @State private var isShowingGuide = false

    public init(model: WorkoutModel, routines: RoutinesModel) {
        _model = State(initialValue: model)
        _routines = State(initialValue: routines)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.isPreparingSession {
                    ProgressView("Preparing workout…")
                } else if model.isSavingSession && !model.isSessionActive {
                    ProgressView("Saving workout…")
                } else if model.isSessionActive {
                    SessionList(model: model, isPickingExercise: $isPickingExercise)
                        .disabled(model.isSavingSession)
                } else if model.needsDraftRecovery {
                    WorkoutRecoveryView(model: model) { isConfirmingDiscard = true }
                } else {
                    StartSessionView(
                        routines: routines,
                        notice: model.draftNotice,
                        onStartEmpty: { model.start() },
                        onStart: { routine in Task { await model.start(routine) } },
                        onEdit: { routineEditor = routines.editor(for: $0) }
                    )
                }
            }
            .navigationTitle("Train")
            .inlineTitle(model.isSessionActive)
            .toolbar { toolbar }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePicker(items: model.exerciseChoices.map(PickerItem.init)) { id in
                    Task { await model.add(exerciseID: id) }
                }
                // Exercises may have been created since this screen first appeared.
                .task { await model.load() }
            }
            .sheet(item: $model.summary) { report in
                SessionReportSheet(content: SessionReportContent(report))
            }
            .sheet(item: $routineEditor) { editor in
                RoutineEditorView(model: editor)
            }
            .sheet(isPresented: $isShowingGuide) {
                SetLoggingGuide(showsRepsInReserve: Binding(
                    get: { model.showsRepsInReserve },
                    set: { showsRIR in Task { await model.setEffortScale(showsRIR ? .repsInReserve : .rpe) } }
                ))
            }
            .confirmationDialog(
                "Discard this session?", isPresented: $isConfirmingDiscard, titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { model.discard() }
            }
            .confirmationDialog(
                "Some exercises are unfinished", isPresented: $model.isConfirmingUnfinished, titleVisibility: .visible
            ) {
                Button("Save without counting them") { Task { await model.finish(countingUnfinished: false) } }
                Button("Count them anyway") { Task { await model.finish(countingUnfinished: true) } }
                Button("Keep training", role: .cancel) {}
            } message: {
                Text(model.unfinishedExplanation)
            }
            .task {
                await model.load()
                await routines.load()
            }
            // A finished session moves the plan on to its next session.
            .onChange(of: model.isSessionActive) { _, isActive in
                if !isActive { Task { await routines.load() } }
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
        if model.isSessionActive && !model.isPreparingSession {
            // Help and focus stay one tap away, so the first set leads the screen.
            ToolbarItem(placement: .cancellationAction) {
                Menu {
                    Button("How to log sets", systemImage: "questionmark.circle") { isShowingGuide = true }
                    Picker(selection: Binding(
                        get: { model.sessionFocus },
                        set: { focus in Task { await model.setSessionFocus(focus) } }
                    )) {
                        Text("Auto").tag(TrainingFocus?.none)
                        ForEach(model.focusOptions) { option in
                            Text(option.name).tag(TrainingFocus?.some(option.value))
                        }
                    } label: {
                        Label("Session focus", systemImage: "scope")
                    }
                    .pickerStyle(.menu)
                    Divider()
                    Button("Discard", systemImage: "trash", role: .destructive) { isConfirmingDiscard = true }
                } label: {
                    Label("Session options", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.isSavingSession)
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isSavingSession {
                    ProgressView()
                        .accessibilityLabel("Saving workout…")
                } else {
                    Button("Finish") { Task { await model.requestFinish() } }
                }
            }
        } else if !model.needsDraftRecovery && !model.isPreparingSession && !model.isSavingSession {
            ToolbarItem(placement: .primaryAction) {
                Button("New routine", systemImage: "plus") { routineEditor = routines.newEditor() }
            }
        }
    }
}

private struct WorkoutRecoveryView: View {
    let model: WorkoutModel
    let onDiscard: () -> Void

    var body: some View {
        List {
            Section {
                if let name = model.recoverableWorkoutName, let start = model.recoverableWorkoutStart {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(name).font(.title2.weight(.semibold))
                        Label {
                            Text(start, format: .dateTime.day().month().year().hour().minute())
                        } icon: {
                            Image(systemName: "clock")
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let message = model.draftErrorMessage {
                    StatusLabel(title: message, tone: .caution)
                }
                if model.isRecoveringDraft {
                    ProgressView()
                } else if model.canResumeWorkout {
                    Button("Resume workout", systemImage: "play.fill") {
                        Task { await model.resumeSavedWorkout() }
                    }
                    .buttonStyle(BrandButtonStyle())
                } else {
                    Button("Try again", systemImage: "arrow.clockwise") { model.retryDraftAccess() }
                }
            } header: {
                Text("Saved workout draft")
            }
            Section {
                Button("Discard saved workout", role: .destructive, action: onDiscard)
                    .disabled(model.isRecoveringDraft)
            }
        }
    }
}

/// The exercises and sets of the session in progress, bound directly to the model.
private struct SessionList: View {
    @Bindable var model: WorkoutModel
    @Binding var isPickingExercise: Bool
    @State private var progressionExercise: DraftExercise.ID?

    var body: some View {
        List {
            Text(model.sessionName)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            // Failures and what fixes them stay above the sets.
            if let message = model.draftErrorMessage {
                StatusLabel(title: message, tone: .caution)
                Button("Retry saving draft", systemImage: "arrow.clockwise") { model.retryDraftAccess() }
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let deload = model.deloadNotice {
                Label(deload, systemImage: "arrow.down.right.circle.fill")
                    .foregroundStyle(.tint)
            }
            ForEach($model.exercises) { $exercise in
                Section {
                    TargetSummaryView(summary: exercise.summary)
                    if let offer = exercise.progressionOffer {
                        Button {
                            model.clearProgressionSaveError()
                            progressionExercise = exercise.id
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Label("Choose progression", systemImage: "chart.line.uptrend.xyaxis")
                                Text(offer.lastSession)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach($exercise.sets) { $set in
                        SetRow(
                            number: exercise.number(of: set.id), set: $set,
                            showsRepsInReserve: model.showsRepsInReserve
                        ) { isDone in
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
                            Button("Add warm-up sets", systemImage: "flame") { model.addWarmUp(to: exercise.id) }
                                .disabled(!exercise.canAddWarmUp)
                            Button("Remove exercise", systemImage: "trash", role: .destructive) {
                                model.removeExercise(exercise.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Exercise options")
                    }
                } footer: {
                    // Optional advice comes after the first exercise's sets, not before them.
                    if exercise.id == model.exercises.first?.id, let tip = model.generalWarmUpTip {
                        Label(tip, systemImage: "figure.walk")
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
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: Binding(
            get: { progressionExercise != nil },
            set: { if !$0 { progressionExercise = nil } }
        )) {
            if let id = progressionExercise {
                ProgressionPicker(model: model, exerciseID: id)
            }
        }
        .keyboardDoneButton()
        .safeAreaInset(edge: .bottom) {
            if model.rest.isActive {
                RestTimerView(model: model.rest)
            }
        }
    }
}

private struct ProgressionPicker: View {
    let model: WorkoutModel
    let exerciseID: DraftExercise.ID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let offer = model.progressionOffer(for: exerciseID) {
                    Text(offer.lastSession).font(.subheadline.monospacedDigit())
                    if let note = offer.note {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(offer.options) { option in
                            Button {
                                Task {
                                    if await model.chooseProgression(option, for: exerciseID) { dismiss() }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                    Text(option.title).font(.headline)
                                    Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                                    Text(option.preview).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                                }
                                .padding(.vertical, Spacing.xSmall)
                            }
                        }
                    } footer: {
                        Text("Choosing an option updates today's sets and saves the method for this exercise.")
                    }
                    .disabled(model.isSavingProgression)
                }
                if model.isSavingProgression {
                    ProgressView("Saving progression…")
                }
                if let message = model.progressionSaveError {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            .navigationTitle("Choose progression")
            .inlineTitle(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(model.isSavingProgression)
                }
            }
        }
        .interactiveDismissDisabled(model.isSavingProgression)
    }
}

/// The engine's target and status for one exercise, with reasons and their evidence level.
private struct TargetSummaryView: View {
    let summary: TargetSummary

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if !summary.isStalled, let explanation = summary.statusExplanation {
                    Text(explanation)
                }
                ForEach(Array(summary.reasons.enumerated()), id: \.offset) { Text($0.element) }
                if !summary.stallSuggestions.isEmpty {
                    Text("Stalled — try, in order:").bold()
                    ForEach(Array(summary.stallSuggestions.enumerated()), id: \.offset) { Text($0.element) }
                }
                ReadingLinks(items: summary.readings.map(ReadingLinkItem.init))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                AdaptiveStack {
                    Text(summary.targetLine).font(.subheadline.monospacedDigit())
                    if let status = summary.status {
                        if summary.isStalled {
                            StatusLabel(title: status, tone: .caution)
                                .font(.caption.weight(.semibold))
                        } else {
                            Text(status)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Label(summary.lastTimeLine, systemImage: "clock.arrow.circlepath")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(summary.focusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // A stall is shown with its reason without opening the details.
                if summary.isStalled, let explanation = summary.statusExplanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SetRow: View {
    let number: Int
    @Binding var set: DraftSet
    let showsRepsInReserve: Bool
    let onDoneChange: (Bool) -> Void

    var body: some View {
        SetEntryRow(number: SetNumberLabel(number, isWarmUp: set.isWarmUp)) {
            SetValueFields(
                weightKg: $set.weightKg, reps: $set.reps, rpe: $set.rpe, showsRepsInReserve: showsRepsInReserve
            )
        } action: {
            Toggle(isOn: Binding(get: { set.isDone }, set: onDoneChange)) {
                Label("Set \(number) done", systemImage: set.isDone ? "checkmark.circle.fill" : "circle")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .toggleStyle(.button)
            // Confirms completion without looking at the screen.
            .sensoryFeedback(.success, trigger: set.isDone) { _, isDone in isDone }
        }
    }
}

extension View {
    /// Leave more vertical room for logging when the session is active.
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
