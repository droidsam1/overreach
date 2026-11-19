import DesignSystem
import HistoryPresentation
import SwiftUI

// Views only: layout, styling and navigation. Texts, e1RM and decisions come from `HistoryPresentation`
// (ADR-0014), so this file can be redesigned freely.

/// How History is shown. Purely visual, so the view keeps it.
private enum HistoryLayout: String {
    case list, calendar
}

/// Past strength sessions with their detail, as a list or as a month calendar with runs and steps.
public struct HistoryView: View {
    @State private var model: HistoryModel
    @AppStorage("history.layout") private var layout = HistoryLayout.list

    public init(model: HistoryModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch layout {
                case .list: sessionList
                case .calendar: HistoryCalendarView(history: model)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show as", selection: $layout) {
                    Text("List").tag(HistoryLayout.list)
                    Text("Calendar").tag(HistoryLayout.calendar)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background(.bar)
            }
            .navigationTitle("History")
            .task { await model.load() }
        }
    }

    private var sessionList: some View {
        List {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            ForEach(model.summaries) { summary in
                NavigationLink {
                    SessionDetailView(model: model, sessionID: summary.id)
                } label: {
                    SessionRow(summary: summary)
                }
            }
            .onDelete { offsets in
                Task { await model.delete(at: offsets) }
            }
        }
        .overlay {
            if model.showsEmptyState {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "calendar",
                    description: Text("Finished sessions appear here.")
                )
            }
        }
        .refreshable { await model.load() }
    }
}

struct SessionRow: View {
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack {
                Text(summary.title).font(.headline)
                Spacer()
                Text(summary.date, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(summary.exerciseList)
                .font(.subheadline)
                .lineLimit(2)
            Text(summary.statsLine())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
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
            if let focus = detail.focus {
                LabeledContent("Focus", value: focus)
            }
            if let notes = detail.notes {
                Text(notes).font(.callout)
            }
        }
    }
}
