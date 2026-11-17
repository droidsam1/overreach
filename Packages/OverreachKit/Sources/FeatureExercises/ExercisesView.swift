import Analytics
import DesignSystem
import Domain
import SwiftUI

/// Exercise list. Phase 1: assign muscles to imported exercises and merge duplicates (issue #13).
/// Progress, e1RM, PRs and stalls per exercise come in phase 3. Pushed inside the caller's navigation stack.
public struct ExercisesView: View {
    @State private var model: ExercisesModel
    @State private var searchText = ""

    public init(model: ExercisesModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        List {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            if searchText.isEmpty, !model.needsMapping.isEmpty {
                Section {
                    ForEach(model.needsMapping) { exercise in
                        row(exercise)
                    }
                } header: {
                    Text("Needs muscles")
                } footer: {
                    Text("Imported exercises that are not in the catalog. Their volume does not count until you assign "
                        + "their muscles or merge them into a catalog exercise.")
                }
            }
            Section("All exercises") {
                ForEach(filtered) { exercise in
                    row(exercise)
                }
            }
        }
        .navigationTitle("Exercises")
        .searchable(text: $searchText)
        .overlay {
            if model.isLoading, model.exercises.isEmpty { ProgressView() }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private var filtered: [Exercise] {
        guard !searchText.isEmpty else { return model.exercises }
        let query = searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return model.exercises.filter { exercise in
            ([exercise.name] + exercise.aliases).contains {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(query)
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        NavigationLink {
            ExerciseMappingView(model: model, exerciseID: exercise.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                Group {
                    if exercise.needsMuscleMapping {
                        Label("No muscles assigned", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    } else {
                        Text(MuscleText.list(exercise.primaryMuscles))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .badge(model.sessionCount(of: exercise.id))
    }
}

/// Edit an exercise's muscles and equipment, copy them from a similar exercise, or merge into another one.
struct ExerciseMappingView: View {
    let model: ExercisesModel
    let exerciseID: UUID

    @State private var primary: Set<MuscleGroup> = []
    @State private var secondary: Set<MuscleGroup> = []
    @State private var equipment: Equipment = .other
    @State private var hasLoaded = false
    @State private var mergeTarget: Exercise?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let exercise = model.exercise(id: exerciseID) {
            form(exercise)
        } else {
            ContentUnavailableView("Exercise removed", systemImage: "trash")
        }
    }

    private func form(_ exercise: Exercise) -> some View {
        Form {
            let suggestions = model.suggestions(for: exercise)
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.exercise.id) { suggestion in
                        suggestionRow(suggestion.exercise, canMerge: exercise.isCustom)
                    }
                } header: {
                    Text("Similar exercises")
                } footer: {
                    Text("Copy fills in the muscles below. Merge moves this exercise's history to the other one.")
                }
            }
            Section {
                Picker("Equipment", selection: $equipment) {
                    ForEach(Equipment.allCases, id: \.self) { item in
                        Text(MuscleText.equipment(item)).tag(item)
                    }
                }
            }
            muscleSection("Primary muscles", footer: "Each working set counts as one set for these muscles.",
                          selection: $primary, other: $secondary)
            muscleSection("Secondary muscles", footer: "Each working set counts as half a set for these muscles.",
                          selection: $secondary, other: $primary)
            if exercise.isCustom {
                Section {
                    NavigationLink("Merge into another exercise…") {
                        MergeTargetList(model: model, source: exercise) { mergeTarget = $0 }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if await model.saveMapping(
                            for: exerciseID, primary: primary, secondary: secondary, equipment: equipment
                        ) {
                            dismiss()
                        }
                    }
                }
                .disabled(primary.isEmpty)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            primary = exercise.primaryMuscles
            secondary = exercise.secondaryMuscles
            equipment = exercise.equipment
        }
        .confirmationDialog(
            "Merge exercises?",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            titleVisibility: .visible,
            presenting: mergeTarget
        ) { target in
            Button("Merge into \(target.name)") {
                Task {
                    if await model.merge(exerciseID, into: target.id) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("\(model.sessionCount(of: exerciseID)) sessions with \(exercise.name) will use \(target.name). "
                + "\(exercise.name) is removed and its name is kept as an alias, so importing it again maps to "
                + "\(target.name).")
        }
    }

    private func suggestionRow(_ candidate: Exercise, canMerge: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.name)
            Text(MuscleText.list(candidate.primaryMuscles))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Copy muscles") {
                    primary = candidate.primaryMuscles
                    secondary = candidate.secondaryMuscles
                    if equipment == .other { equipment = candidate.equipment }
                }
                if canMerge {
                    Spacer()
                    Button("Merge") { mergeTarget = candidate }
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private func muscleSection(
        _ title: LocalizedStringKey,
        footer: LocalizedStringKey,
        selection: Binding<Set<MuscleGroup>>,
        other: Binding<Set<MuscleGroup>>
    ) -> some View {
        Section {
            ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                Toggle(MuscleText.muscle(muscle), isOn: Binding(
                    get: { selection.wrappedValue.contains(muscle) },
                    set: { isOn in
                        if isOn {
                            selection.wrappedValue.insert(muscle)
                            other.wrappedValue.remove(muscle)
                        } else {
                            selection.wrappedValue.remove(muscle)
                        }
                    }
                ))
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }
}

/// Every mapped exercise, searchable, to pick a merge target.
private struct MergeTargetList: View {
    let model: ExercisesModel
    let source: Exercise
    let onPick: (Exercise) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(targets) { target in
            Button {
                onPick(target)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name).foregroundStyle(.primary)
                    Text(MuscleText.list(target.primaryMuscles)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Merge into")
        .searchable(text: $searchText)
    }

    private var targets: [Exercise] {
        let all = model.mergeTargets(for: source)
        guard !searchText.isEmpty else { return all }
        let query = searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return all.filter { exercise in
            ([exercise.name] + exercise.aliases).contains {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(query)
            }
        }
    }
}

/// Display names for muscles and equipment.
enum MuscleText {
    static func muscle(_ muscle: MuscleGroup) -> LocalizedStringKey {
        switch muscle {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .quadriceps: "Quadriceps"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .core: "Core"
        }
    }

    static func equipment(_ equipment: Equipment) -> LocalizedStringKey {
        switch equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .other: "Other"
        }
    }

    /// "Chest, Triceps" — for compact rows.
    static func list(_ muscles: Set<MuscleGroup>) -> String {
        MuscleGroup.allCases.filter(muscles.contains).map { $0.rawValue.capitalized }.joined(separator: ", ")
    }
}
