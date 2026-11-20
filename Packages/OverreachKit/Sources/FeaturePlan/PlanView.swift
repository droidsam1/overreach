import DesignSystem
import Domain
import PlanPresentation
import PresentationKit
import SwiftUI

// Views only: layout, styling and navigation. Goal rules, texts and options come from `PlanPresentation`
// (ADR-0014), so this file can be redesigned freely.

/// Goal, current block, what to do next, balance findings and the plan for the coming months (ADR-0013).
public struct PlanView<Assistant: View>: View {
    @State private var model: PlanModel
    @State private var showsDeloadHistory = false
    private let assistant: Assistant

    /// - Parameter assistant: links to other features (e.g. "Ask AI"). Wired by the app.
    public init(model: PlanModel, @ViewBuilder assistant: () -> Assistant) {
        _model = State(initialValue: model)
        self.assistant = assistant()
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
                if let next = model.next {
                    Section("Next") {
                        Text(next.headline).font(.headline)
                        if !next.reasons.isEmpty {
                            DisclosureGroup("Why this recommendation?") {
                                ExplainedLines(lines: next.reasons)
                            }
                        }
                    }
                }
                currentBlockSection
                if model.lastDeloadSummary != nil || !model.pendingDeloadRows.isEmpty { deloadSection }
                planSection
                if !model.findingLines.isEmpty {
                    Section("Worth a look") {
                        ExplainedLines(lines: model.findingLines)
                    }
                }
                goalSection
                blockSection
                Section { assistant }
            }
            .navigationTitle("Plan")
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    private var deloadSection: some View {
        Section("Recovery history") {
            if let summary = model.lastDeloadSummary {
                Text(summary)
            }
            if !model.deloadRows.isEmpty {
                DisclosureGroup("Deloads and rest periods", isExpanded: $showsDeloadHistory) {
                    ForEach(model.deloadRows) { row in
                        deloadDetails(row)
                    }
                }
            }
            ForEach(model.pendingDeloadRows) { row in
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text("Count this period as a deload?").bold()
                    deloadDetails(row)
                    Button("Count as deload") {
                        Task { await model.reviewDeload(start: row.id, accepted: true) }
                    }
                    Button("Dismiss") {
                        Task { await model.reviewDeload(start: row.id, accepted: false) }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isReviewingDeload)
            }
        }
    }

    private func deloadDetails(_ row: DeloadRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(row.start...row.end)
            Text(row.reason.text).foregroundStyle(.secondary)
            Text(row.reason.evidence).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var goalSection: some View {
        Section("Goal") {
            Picker("Goal", selection: Binding(
                get: { model.goalKind },
                set: { kind in Task { await model.setGoal(kind: kind) } }
            )) {
                ForEach(model.goalOptions) { option in
                    Text(option.name).tag(option.value)
                }
            }
            Toggle("Target date", isOn: Binding(
                get: { model.hasTargetDate },
                set: { isOn in Task { await model.setHasTargetDate(isOn) } }
            ))
            if model.hasTargetDate {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { model.targetDate },
                        set: { date in Task { await model.setTargetDate(date) } }
                    ),
                    displayedComponents: .date
                )
            }
            if model.showsPriorityLifts {
                NavigationLink("Priority lifts (\(model.priorityLiftCount))") {
                    PriorityLiftsView(model: model)
                }
            }
            if model.showsRunningPlan {
                NavigationLink {
                    RunningPlanView(model: model)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Running goal")
                        if let summary = model.runningGoalSummary {
                            Text(summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if model.showsRunningCalendar {
                NavigationLink("Running calendar") { RunningCalendarView(model: model) }
            }
        }
    }

    private var currentBlockSection: some View {
        Section("Current block") {
            if let title = model.currentBlockTitle, let start = model.currentBlockStart {
                Text(title).font(.headline)
                LabeledContent("Since", value: start.formatted(date: .abbreviated, time: .omitted))
            } else {
                Text("No training logged yet.").foregroundStyle(.secondary)
            }
        }
    }

    private var blockSection: some View {
        Section {
            Picker("New block", selection: $model.newBlockFocus) {
                ForEach(model.focusOptions) { option in
                    Text(option.name).tag(option.value)
                }
            }
            Stepper("\(model.newBlockWeeks) weeks", value: $model.newBlockWeeks, in: model.newBlockWeeksRange)
            Button("Start this block today") {
                Task { await model.startNewBlock() }
            }
        } header: {
            Text("New block")
        } footer: {
            Text("Declaring a block tells the app a run of similar sessions is intentional.")
        }
    }

    private var planSection: some View {
        Section {
            ForEach(model.planRows) { row in
                AdaptiveStack {
                    Text(row.title)
                        .foregroundStyle(row.isDeload ? .secondary : .primary)
                    Spacer()
                    Text(row.start.formatted(.dateTime.day().month()))
                        .foregroundStyle(.secondary)
                    Text("\(row.weeks) wk").monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Coming months")
        } footer: {
            Text("A draft from your goal. Block lengths are coaching heuristics; adjust as you go.")
        }
    }
}

/// Rule explanations, each with the strength of its evidence.
private struct ExplainedLines: View {
    let lines: [ExplainedLine]

    var body: some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(line.text)
                Text(line.evidence).font(.caption).foregroundStyle(.secondary)
                ReadingLinks(items: line.readings.map(ReadingLinkItem.init))
            }
        }
    }
}

private struct PriorityLiftsView: View {
    @Bindable var model: PlanModel

    var body: some View {
        List(model.priorityLiftRows) { row in
            Button {
                Task { await model.togglePriorityLift(row.id) }
            } label: {
                HStack {
                    Text(row.name)
                    Spacer()
                    if row.isSelected {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityAddTraits(row.isSelected ? .isSelected : [])
        }
        .overlay {
            if model.priorityLiftRows.isEmpty {
                ListEmptyState(query: model.priorityLiftSearch, title: "No exercises", systemImage: "dumbbell")
            }
        }
        .searchable(text: $model.priorityLiftSearch)
        .navigationTitle("Priority lifts")
    }
}

extension PlanView where Assistant == EmptyView {
    public init(model: PlanModel) {
        self.init(model: model) { EmptyView() }
    }
}

extension ReadingLinkItem {
    /// The display values of a curated reading (ADR-0027).
    init(_ reading: Reading) {
        self.init(url: reading.url, title: reading.title, detail: reading.detail(), note: reading.note)
    }
}
