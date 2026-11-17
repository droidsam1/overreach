import Analytics
import DesignSystem
import Domain
import SwiftUI

/// Goal, current block, what to do next, balance findings and the plan for the coming months (ADR-0013).
public struct PlanView: View {
    @State private var model: PlanModel
    @State private var newBlockFocus: TrainingFocus = .hypertrophy
    @State private var newBlockWeeks = 6
    @State private var goalKind: TrainingGoal.Kind = .general
    @State private var hasTargetDate = false
    @State private var targetDate = Date().addingTimeInterval(16 * 7 * 86_400)

    public init(model: PlanModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if model.isAnalysing {
                    HStack {
                        ProgressView()
                        Text("Analysing your history…").foregroundStyle(.secondary)
                    }
                }
                goalSection
                blockSection
                if let suggestion = model.suggestion {
                    suggestionSection(suggestion)
                }
                if !model.findings.isEmpty {
                    Section("Worth a look") {
                        ForEach(Array(model.findings.enumerated()), id: \.offset) { _, finding in
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(finding.text(names: model.exerciseNames))
                                Text(finding.evidence.level.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                planSection
            }
            .navigationTitle("Plan")
            .task {
                await model.load()
                goalKind = model.goalKind
                hasTargetDate = model.profile.goal?.targetDate != nil
                if let day = model.profile.goal?.targetDate { targetDate = day.startDate() }
            }
            .refreshable { await model.load() }
        }
    }

    private var goalSection: some View {
        Section("Goal") {
            Picker("Goal", selection: $goalKind) {
                ForEach(TrainingGoal.Kind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .onChange(of: goalKind) {
                guard goalKind != model.goalKind else { return }
                Task { await model.setGoal(kind: goalKind) }
            }
            Toggle("Target date", isOn: $hasTargetDate)
                .onChange(of: hasTargetDate) {
                    guard hasTargetDate != (model.profile.goal?.targetDate != nil) else { return }
                    Task { await model.setTargetDate(hasTargetDate ? targetDate : nil) }
                }
            if hasTargetDate {
                DatePicker("Date", selection: $targetDate, displayedComponents: .date)
                    .onChange(of: targetDate) {
                        Task { await model.setTargetDate(targetDate) }
                    }
            }
            if model.goalKind == .strength {
                NavigationLink("Priority lifts (\(model.profile.goal?.priorityLifts.count ?? 0))") {
                    PriorityLiftsView(model: model)
                }
            }
        }
    }

    private var blockSection: some View {
        Section {
            if let block = model.currentBlock {
                LabeledContent("Current block", value: "\(block.focus.title)\(block.isDeclared ? "" : " (detected)")")
                LabeledContent("Since", value: block.start.startDate().formatted(date: .abbreviated, time: .omitted))
            } else {
                Text("No training logged yet.").foregroundStyle(.secondary)
            }
            Picker("New block", selection: $newBlockFocus) {
                ForEach(TrainingFocus.allCases, id: \.self) { focus in
                    Text(focus.title).tag(focus)
                }
            }
            Stepper("\(newBlockWeeks) weeks", value: $newBlockWeeks, in: 1...16)
            Button("Start this block today") {
                Task { await model.startBlock(focus: newBlockFocus, weeks: newBlockWeeks) }
            }
        } header: {
            Text("Block")
        } footer: {
            Text("Declaring a block tells the app a run of similar sessions is intentional.")
        }
    }

    private func suggestionSection(_ suggestion: BlockSuggestion) -> some View {
        Section("Next") {
            let when = suggestion.switchInWeeks == 0 ? "now" : "in \(suggestion.switchInWeeks) weeks"
            let length = "\(suggestion.nextLengthWeeks.lowerBound)–\(suggestion.nextLengthWeeks.upperBound) weeks"
            Text("\(suggestion.next.title) block \(when), for \(length).").bold()
            ForEach(Array(suggestion.reasons.enumerated()), id: \.offset) { _, reason in
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(reason.text)
                    Text(reason.evidence.level.label).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var planSection: some View {
        Section {
            ForEach(Array(model.plan.enumerated()), id: \.offset) { _, block in
                HStack {
                    Text(block.focus?.title ?? "Deload")
                        .foregroundStyle(block.isDeload ? .secondary : .primary)
                    Spacer()
                    Text(block.start.startDate().formatted(.dateTime.day().month()))
                        .foregroundStyle(.secondary)
                    Text("\(block.weeks) wk").monospacedDigit()
                }
            }
        } header: {
            Text("Coming months")
        } footer: {
            Text("A draft from your goal. Block lengths are coaching heuristics; adjust as you go.")
        }
    }
}

private struct PriorityLiftsView: View {
    let model: PlanModel
    @State private var query = ""

    private var filtered: [Exercise] {
        query.isEmpty ? model.catalog : model.catalog.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(filtered) { exercise in
            Button {
                Task { await model.togglePriorityLift(exercise.id) }
            } label: {
                HStack {
                    Text(exercise.name)
                    Spacer()
                    if model.profile.goal?.priorityLifts.contains(exercise.id) == true {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Priority lifts")
    }
}
