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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    if let message = model.errorMessage {
                        InlineNotice(Text(message), tone: .critical) { Task { await reload() } }
                    }
                    nextSessionCard
                    weekCard
                    if let row = model.pendingDeloadRows.first {
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.small) {
                                SectionHeader(Text("Recent break"))
                                DeloadQuestionView(model: model, row: row)
                            }
                        }
                    }
                    links
                }
                .padding(Spacing.medium)
            }
            .navigationTitle("Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .haptic(.completed, trigger: model.savedChangeCount)
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

    @ViewBuilder private var nextSessionCard: some View {
        if let row = model.nextSessionRows.first {
            switch row {
            case let .run(run):
                sessionCard(title: run.title, date: run.date) { runEditor = model.editRunningEntry(run.entry) }
            case let .strength(strength):
                sessionCard(title: strength.title, date: strength.date) {
                    strengthEditor = model.editStrengthEntry(strength.entry)
                }
            }
        } else if model.next != nil || model.showsHybridCalendar || model.isAnalysing {
            Card {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    SectionHeader(Text("Next"))
                    if let next = model.next {
                        Text(next.headline).font(.title2.bold())
                        if !next.reasons.isEmpty {
                            DisclosureGroup("Why this recommendation?") {
                                ExplainedLines(lines: next.reasons)
                            }
                        }
                    } else if model.isAnalysing {
                        LoadingState("Analysing your history…")
                    } else {
                        Text("No dated sessions. Today follows your usual rotation until you schedule one.")
                            .foregroundStyle(.secondary)
                    }
                    if let rotation = model.pendingRotationSummary {
                        Label(rotation, systemImage: "repeat").foregroundStyle(.secondary)
                    }
                    if model.showsHybridCalendar {
                        NavigationLink {
                            HybridCalendarView(model: model)
                        } label: {
                            Text("Hybrid calendar").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func sessionCard(title: String, date: String, edit: @escaping () -> Void) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SectionHeader(Text("Next"))
                Text(title).font(.title2.bold())
                Text(date).foregroundStyle(.secondary)
                Button(action: edit) {
                    Text("Edit session").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder private var weekCard: some View {
        let days = model.weekDays
        if !days.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    SectionHeader(Text("Your week"))
                    PlanWeekStrip(days: days)
                    if let week = model.progress?.week { progressLine(week) }
                }
            }
        }
    }

    private func progressLine(_ line: PlanProgress.Line) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ProgressBar(
                segments: [.init(fraction: line.fraction, color: StatusTone.positive.accent)],
                accessibilityLabel: line.accessibilityLabel, accessibilityValue: ""
            )
            .accessibilityHidden(true)
            Text(line.title).font(.subheadline).accessibilityLabel(Text(line.accessibilityLabel))
        }
    }

    private func reload() async {
        await model.load()
        await model.loadCalendarRoutines()
    }

    private var links: some View {
        VStack(spacing: Spacing.small) {
            if model.showsHybridCalendar {
                NavigationLink {
                    HybridCalendarView(model: model)
                } label: {
                    linkTile(Text("Calendar"), symbol: "calendar")
                }
            }
            NavigationLink {
                GoalEditView(model: model)
            } label: {
                linkTile(Text("Goal"), symbol: "target", detail: model.goalSummary)
            }
            NavigationLink {
                blockDetails
            } label: {
                linkTile(Text("Current block"), symbol: "square.stack", detail: model.currentBlockTitle)
            }
            if Progress.self != EmptyView.self {
                NavigationLink {
                    progress
                } label: {
                    linkTile(Text("View progress"), symbol: "chart.line.uptrend.xyaxis", detail: model.progressSummary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func linkTile(_ title: Text, symbol: String, detail: String? = nil) -> some View {
        Card(radius: Radius.tile) {
            HStack(spacing: Spacing.small) {
                IconTile(symbolName: symbol, color: StatusTone.positive.accent)
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    title.font(.headline)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var blockDetails: some View {
        Form {
            if let message = model.errorMessage {
                InlineNotice(Text(message), tone: .critical) { Task { await reload() } }
            }
            currentBlockSection
            if !model.specializationOptions.isEmpty {
                Section {
                    NavigationLink("Muscle priorities") {
                        Form {
                            Section {
                                ForEach(model.specializationOptions, id: \.value) { option in
                                    Toggle(
                                        option.name,
                                        isOn: Binding(
                                            get: { model.specializedMuscles.contains(option.value) },
                                            set: { _ in Task { await model.toggleSpecialization(option.value) } }
                                        )
                                    )
                                    .disabled(model.isSavingProfile)
                                }
                            } footer: {
                                Text("Choose muscles this block intentionally prioritizes.")
                            }
                        }
                        .navigationTitle("Muscle priorities")
                    }
                }
            }
            if !model.muscleBalanceRows.isEmpty {
                Section("Muscle balance") {
                    ForEach(model.muscleBalanceRows) { row in
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(row.text)
                                Text(row.evidenceText).font(.footnote).foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)

                            Button {
                                model.dismissMuscleBalance(row.id)
                            } label: {
                                Text("Dismiss")
                                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text(row.dismissAccessibilityLabel))
                        }
                    }
                }
            }
            if !model.pendingDeloadRows.isEmpty {
                Section("Recent break") {
                    ForEach(model.pendingDeloadRows) { row in
                        DeloadQuestionView(model: model, row: row)
                    }
                }
            }
            if !model.findingLines.isEmpty {
                Section("Worth a look") { ExplainedLines(lines: model.findingLines) }
            }
            if let next = model.next {
                Section("Next") {
                    Text(next.headline).font(.headline)
                    ExplainedLines(lines: next.reasons)
                }
            }
            planSection
            blockSection
            if Assistant.self != EmptyView.self { Section { assistant } }
        }
        .navigationTitle("Current block")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var currentBlockSection: some View {
        Section("Current block") {
            if let block = model.progress?.block { progressLine(block) }
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
                InlineNotice(Text(message), tone: .critical)
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
