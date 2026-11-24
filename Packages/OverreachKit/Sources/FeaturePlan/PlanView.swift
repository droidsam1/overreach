import DesignSystem
import Domain
import PlanPresentation
import PresentationKit
import SwiftUI

// Views only: layout, styling and navigation. Goal rules, texts and options come from `PlanPresentation`
// (ADR-0014), so this file can be redesigned freely.

/// What is coming up and how to change it: the next sessions and the calendar, the current block, the goal summary
/// and the plan for the coming months (ADR-0013). Progress lives in Recovery & Progress.
public struct PlanView<Assistant: View, Progress: View>: View {
    @State private var model: PlanModel
    @State private var runEditor: RunningCalendarDraft?
    @State private var strengthEditor: StrengthCalendarDraft?
    @Binding private var suggestedRun: RunningCalendarDraft?
    private let assistant: Assistant
    private let progress: Progress

    /// - Parameters:
    ///   - assistant: links to other features (e.g. "Ask AI"). Wired by the app.
    ///   - progress: where "View progress" goes (Recovery & Progress). Wired by the app.
    public init(
        model: PlanModel, suggestedRun: Binding<RunningCalendarDraft?> = .constant(nil),
        @ViewBuilder assistant: () -> Assistant, @ViewBuilder progress: () -> Progress
    ) {
        _model = State(initialValue: model)
        _suggestedRun = suggestedRun
        self.assistant = assistant()
        self.progress = progress()
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
                progressHeader
                if model.showsHybridCalendar { scheduleSection }
                if !model.pendingDeloadRows.isEmpty {
                    Section("Recent break") {
                        ForEach(model.pendingDeloadRows) { row in
                            DeloadQuestionView(model: model, row: row)
                        }
                    }
                }
                currentBlockSection
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
                goalSection
                planSection
                if !model.findingLines.isEmpty {
                    Section("Worth a look") {
                        ExplainedLines(lines: model.findingLines)
                    }
                }
                blockSection
                if Progress.self != EmptyView.self { progressSection }
                Section { assistant }
            }
            .navigationTitle("Plan")
            .task { await reload() }
            .onChange(of: suggestedRun, initial: true) { _, draft in
                guard let draft else { return }
                runEditor = draft
                suggestedRun = nil
            }
            .refreshable { await reload() }
            .calendarEditors(model: model, run: $runEditor, strength: $strengthEditor)
        }
    }

    /// Real progress through the plan: sessions done this week and the block's week (ADR-0041 rule 7). Each bar
    /// carries its value as text, and VoiceOver reads one sentence per line.
    @ViewBuilder private var progressHeader: some View {
        if let progress = model.progress {
            Section {
                ForEach(progress.lines, id: \.title) { line in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(line.title).font(.subheadline.weight(.semibold))
                        ProgressView(value: line.fraction)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(line.accessibilityLabel))
                }
            }
        }
    }

    private func reload() async {
        await model.load()
        await model.loadCalendarRoutines()
    }

    /// The next dated sessions, each opening its editor to move or change it, and the whole calendar.
    private var scheduleSection: some View {
        Section {
            if let rotation = model.pendingRotationSummary {
                Label(rotation, systemImage: "repeat")
            }
            if model.nextSessionRows.isEmpty, model.pendingRotationSummary == nil {
                Text("No dated sessions. Today follows your usual rotation until you schedule one.")
                    .foregroundStyle(.secondary)
            }
            CalendarRows(
                model: model, rows: model.nextSessionRows, runEditor: $runEditor, strengthEditor: $strengthEditor
            )
            NavigationLink(model.hasMoreSessions ? "All training days" : "Hybrid calendar") {
                HybridCalendarView(model: model)
            }
        } header: {
            Text("Upcoming sessions")
        }
    }

    private var goalSection: some View {
        Section("Goal") {
            NavigationLink {
                GoalEditView(model: model)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(model.goalSummary)
                    if model.showsRunningPlan, let summary = model.runningGoalSummary {
                        Text(summary).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var progressSection: some View {
        Section {
            NavigationLink {
                progress
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text("View progress")
                    Text(model.progressSummary).font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Progress")
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

/// Goal, target date, priorities, running goal and the calendar: everything that changes what the plan aims at.
private struct GoalEditView: View {
    let model: PlanModel

    var body: some View {
        Form {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Section {
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
                if model.showsDisciplinePriority {
                    Picker("Priority", selection: Binding(
                        get: { model.disciplinePriority },
                        set: { priority in Task { await model.setPriority(priority) } }
                    )) {
                        ForEach(model.priorityOptions) { option in
                            Text(option.name).tag(option.value)
                        }
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
                if model.showsHybridCalendar {
                    NavigationLink("Hybrid calendar") { HybridCalendarView(model: model) }
                }
            }
        }
        .navigationTitle("Goal")
    }
}

/// Rule explanations, each with the strength of its evidence.
struct ExplainedLines: View {
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

extension PlanView where Assistant == EmptyView, Progress == EmptyView {
    public init(model: PlanModel) {
        self.init(model: model, assistant: { EmptyView() }, progress: { EmptyView() })
    }
}

extension ReadingLinkItem {
    /// The display values of a curated reading (ADR-0030).
    init(_ reading: Reading) {
        self.init(url: reading.url, title: reading.title, detail: reading.detail(), note: reading.note)
    }
}
