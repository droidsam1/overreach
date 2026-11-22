import DesignSystem
import Domain
import HistoryPresentation
import SwiftUI

// Views only: layout, styling and navigation. Texts, e1RM and decisions come from `HistoryPresentation`
// (ADR-0014), so this file can be redesigned freely.

/// How History is shown. Purely visual, so the view keeps it.
private enum HistoryLayout: String {
    case list, calendar
}

/// Strength and runs in a timeline or a month calendar, with steps in the calendar.
public struct HistoryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: HistoryModel
    @AppStorage("history.layout") private var layout = HistoryLayout.list

    private let onOpenTrain: () -> Void

    private var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    public init(model: HistoryModel, onOpenTrain: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onOpenTrain = onOpenTrain
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch layout {
                case .list: activityList
                case .calendar: HistoryCalendarView(history: model)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Group {
                    if typeSize.isAccessibilitySize {
                        layoutPicker
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        layoutPicker
                            .pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background(.bar)
            }
            .navigationTitle("History")
            .task { await model.load() }
        }
    }

    private var layoutPicker: some View {
        Picker("Show as", selection: $layout) {
            Text("List").tag(HistoryLayout.list)
            Text("Calendar").tag(HistoryLayout.calendar)
        }
    }

    private var activityList: some View {
        let companions = model.walkCompanionDetails
        return List {
            filters
            if let last = model.lastTime {
                lastTimeCard(last)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let warning = model.runWarning {
                StatusLabel(title: warning, tone: .caution)
            }
            RunMatchReviewLink(history: model, calendar: false)
            StrengthMatchReviewLink(history: model, calendar: false)
            ForEach(model.rows) { row in
                switch row {
                case let .session(summary):
                    NavigationLink {
                        SessionDetailView(model: model, sessionID: summary.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(ActivityColor.strength)
                                .accessibilityHidden(true)
                            SessionRow(summary: summary, showsSources: true)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await model.delete(summary.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                case let .recording(recording):
                    NavigationLink {
                        RecordedStrengthDetail(recording: recording, model: model)
                    } label: {
                        RecordedStrengthRow(recording: recording)
                    }
                case let .run(run):
                    NavigationLink {
                        HistoryRunDetail(run: run, history: model)
                    } label: {
                        HistoryRunRow(run: run)
                    }
                case let .walk(walk):
                    HistoryWalkRow(walk: walk, companion: companions[walk.id]) {
                        model.answerWalk(walk.id, withDog: $0)
                    }
                }
            }
            if model.isLoading && model.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if model.showsEmptyState {
                ContentUnavailableView {
                    Label("No activities yet", systemImage: "calendar")
                } description: {
                    Text("Finished workouts and runs from connected sources appear here.")
                } actions: {
                    Button("Open Train", action: onOpenTrain)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else if model.showsFilteredEmptyState {
                ContentUnavailableView("No matching activities", systemImage: "line.3.horizontal.decrease.circle")
                Button("Clear search and filters") { model.clearFilters() }
            }
        }
        .refreshable { await model.load() }
        .searchable(
            text: $model.searchText,
            placement: searchPlacement,
            prompt: "Search exercises, runs, sources"
        )
    }

    private func lastTimeCard(_ last: LastExerciseResult) -> some View {
        Section("Last time") {
            NavigationLink {
                SessionDetailView(model: model, sessionID: last.sessionID)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(last.exerciseName).font(.headline)
                    Text(last.date, format: .dateTime.weekday().day().month().year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(Array(last.sets.enumerated()), id: \.offset) { _, set in
                        Text(set).font(.subheadline.monospacedDigit())
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var filters: some View {
        Menu {
            Picker("Activity type", selection: $model.activityFilter) {
                ForEach(HistoryActivityFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            Picker("Source", selection: $model.sourceFilter) {
                Text("All sources").tag(DataSourceKind?.none)
                ForEach(model.sourceOptions) { option in
                    Text(option.name).tag(DataSourceKind?.some(option.value))
                }
            }
            if model.hasFilters {
                Button("Clear filters", systemImage: "arrow.counterclockwise") { model.clearFilters() }
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                if model.hasFilters {
                    Text(model.filterSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

struct SessionRow: View {
    let summary: SessionSummary
    var showsSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(summary.title).font(.headline)
            if showsSources {
                Text(summary.date, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(summary.exerciseList)
                .font(.subheadline)
                .lineLimit(2)
            Text(summary.statsLine())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if showsSources {
                Text(summary.sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One session's sets, with an Edit button. Reads the session from the model so it reflects saved edits.
struct SessionDetailView: View {
    @Bindable var model: HistoryModel
    let sessionID: UUID
    @State private var editor: SessionEditorModel?

    init(model: HistoryModel, sessionID: UUID) {
        self.model = model
        self.sessionID = sessionID
    }

    var body: some View {
        if let detail = model.detail(for: sessionID) {
            content(detail)
                .toolbar {
                    Button("View summary", systemImage: "list.bullet.clipboard") {
                        Task { await model.showReport(for: sessionID) }
                    }
                    Button("Save as routine", systemImage: "square.and.arrow.down") {
                        Task { await model.saveAsRoutine(sessionID: sessionID) }
                    }
                    Button("Edit") { editor = model.makeEditor(forSessionID: sessionID) }
                }
                .sheet(item: $editor) { editor in
                    SessionEditorView(model: editor) { model.didSave($0) }
                }
                .sheet(item: $model.report) { report in
                    SessionReportSheet(content: SessionReportContent(report))
                }
                .alert(
                    model.routineNotice ?? "",
                    isPresented: Binding(
                        get: { model.routineNotice != nil },
                        set: { if !$0 { model.clearRoutineNotice() } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                }
        } else {
            ContentUnavailableView("Session not found", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func content(_ detail: SessionDetail) -> some View {
        List {
            SessionInfo(detail: detail)
            if let recording = detail.recording {
                RecordedStrengthMetrics(recording: recording)
                Section {
                    Button("Undo strength match") {
                        model.separateStrengthMatch(for: sessionID)
                    }
                }
            }
            ForEach(detail.entries) { entry in
                Section(entry.name) {
                    ForEach(entry.sets) { set in
                        AdaptiveStack {
                            Text("\(set.number)").foregroundStyle(.secondary)
                            Text(set.text).monospacedDigit()
                            Spacer()
                            if let estimate = set.estimatedOneRepMax {
                                Text(estimate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let notes = entry.notes {
                        Text(notes).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !entry.countsForProgression {
                        Label("Unfinished: not counted for progression", systemImage: "flag")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle(detail.name)
    }
}

/// Date, duration, focus and notes of a session.
private struct SessionInfo: View {
    let detail: SessionDetail

    var body: some View {
        Section {
            LabeledContent("Date") {
                Text(detail.startedAt, format: .dateTime.weekday().day().month().year().hour().minute())
            }
            if let duration = detail.durationSeconds {
                LabeledContent("Duration") {
                    Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                }
            }
            LabeledContent("Sources", value: detail.sourceText)
            if let focus = detail.focus {
                LabeledContent("Focus", value: focus)
            }
            if let notes = detail.notes {
                Text(notes).font(.callout)
            }
        }
    }
}
