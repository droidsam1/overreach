import Analytics
import DesignSystem
import Domain
import SwiftUI

/// The live session logger (phase 1). Routines come in a later PR.
public struct WorkoutView: View {
    @State private var model: WorkoutModel
    @State private var isPickingExercise = false
    @State private var isConfirmingDiscard = false

    public init(model: WorkoutModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.isSessionActive {
                    SessionList(model: model, isPickingExercise: $isPickingExercise)
                } else {
                    ContentUnavailableView {
                        Label("No session in progress", systemImage: "dumbbell")
                    } description: {
                        Text("Start a session and add exercises. Targets come from your history.")
                    } actions: {
                        Button("Start session") { model.start() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(model.isSessionActive ? model.sessionName : "Train")
            .toolbar { toolbar }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePicker(exercises: model.catalog) { exercise in
                    Task { await model.add(exercise) }
                }
            }
            .confirmationDialog("Discard this session?", isPresented: $isConfirmingDiscard) {
                Button("Discard", role: .destructive) { model.discard() }
            }
            .task { await model.load() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.isSessionActive {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", role: .destructive) { isConfirmingDiscard = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish") { Task { await model.finish() } }
            }
        }
    }
}

/// The exercises and sets of the session in progress, bound directly to the model.
private struct SessionList: View {
    @Bindable var model: WorkoutModel
    @Binding var isPickingExercise: Bool

    var body: some View {
        List {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            ForEach($model.exercises) { $exercise in
                Section {
                    TargetSummary(exercise: exercise)
                    ForEach($exercise.sets) { $set in
                        SetRow(number: (exercise.sets.firstIndex { $0.id == set.id } ?? 0) + 1, set: $set)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    model.removeSet(set.id, from: exercise.id)
                                }
                            }
                    }
                    Button("Add set", systemImage: "plus") { model.addSet(to: exercise.id) }
                } header: {
                    HStack {
                        Text(exercise.exercise.name)
                        Spacer()
                        Menu {
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
            Button("Add exercise", systemImage: "plus.circle.fill") { isPickingExercise = true }
        }
    }
}

/// The engine's target and status for one exercise, with reasons and their evidence level.
private struct TargetSummary: View {
    let exercise: DraftExercise

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(Array(exercise.target.reasons.enumerated()), id: \.offset) { _, reason in
                    Text("\(reason.text) (\(reason.evidence.level.label))")
                }
                if case let .stalled(suggestions) = exercise.status {
                    Text("Stalled — try, in order:").bold()
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Text("\(index + 1). \(suggestion.text) (\(suggestion.evidence.level.label))")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } label: {
            HStack {
                Text(targetLine).font(.subheadline.monospacedDigit())
                Spacer()
                if let status = exercise.status.text {
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(exercise.status.isStalled ? .orange : .secondary)
                }
            }
        }
    }

    private var targetLine: String {
        guard let first = exercise.target.sets.first else { return "Target: –" }
        let weight = first.weightKg.map { "\($0.formatted()) kg × " } ?? ""
        let reps = exercise.target.sets.map { String($0.reps) }.joined(separator: "/")
        return "Target: \(weight)\(reps) @ RPE \(first.targetRPE.formatted())"
    }
}

private struct SetRow: View {
    let number: Int
    @Binding var set: DraftSet

    private static let rpeValues: [Double] = Array(stride(from: 6.0, through: 10.0, by: 0.5))

    var body: some View {
        HStack(spacing: Spacing.small) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("kg", value: $set.weightKg, format: .number)
                .numericKeyboard(decimal: true)
                .multilineTextAlignment(.trailing)
            Text("kg").foregroundStyle(.secondary)
            TextField("reps", value: $set.reps, format: .number)
                .numericKeyboard(decimal: false)
                .multilineTextAlignment(.trailing)
            Text("reps").foregroundStyle(.secondary)
            Picker("RPE", selection: $set.rpe) {
                Text("RPE –").tag(Double?.none)
                ForEach(Self.rpeValues, id: \.self) { value in
                    Text("RPE \(value.formatted())").tag(Double?.some(value))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Toggle(isOn: $set.isDone) {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Set \(number) done")
        }
        .opacity(set.isDone ? 0.6 : 1)
    }
}

private extension View {
    @ViewBuilder
    func numericKeyboard(decimal: Bool) -> some View {
        #if os(iOS)
        keyboardType(decimal ? .decimalPad : .numberPad)
        #else
        self
        #endif
    }
}

/// Searchable list of exercises.
private struct ExercisePicker: View {
    let exercises: [Exercise]
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Exercise] {
        guard !query.isEmpty else { return exercises }
        return exercises.filter { exercise in
            exercise.name.localizedCaseInsensitiveContains(query)
                || exercise.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button(exercise.name) {
                    onPick(exercise)
                    dismiss()
                }
            }
            .searchable(text: $query)
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
