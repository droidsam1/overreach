import DesignSystem
import HistoryPresentation
import SwiftUI

// Views only: layout, styling and navigation. Texts, e1RM and decisions come from `HistoryPresentation`
// (ADR-0014), so this file can be redesigned freely.

/// Past strength sessions with their detail (phase 1). Runs join in phase 2.
public struct HistoryView: View {
    @State private var model: HistoryModel

    public init(model: HistoryModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
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
            .navigationTitle("History")
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }
}

private struct SessionRow: View {
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
private struct SessionDetailView: View {
    let model: HistoryModel
    let sessionID: UUID
    @State private var editor: SessionEditorModel?

    var body: some View {
        if let detail = model.detail(for: sessionID) {
            content(detail)
                .toolbar {
                    Button("Save as routine", systemImage: "square.and.arrow.down") {
                        Task { await model.saveAsRoutine(sessionID: sessionID) }
                    }
                    Button("Edit") { editor = model.makeEditor(forSessionID: sessionID) }
                }
                .sheet(item: $editor) { editor in
                    SessionEditorView(model: editor) { model.didSave($0) }
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
                        HStack {
                            Text("\(set.number)").foregroundStyle(.secondary)
                            Text(set.text).monospacedDigit()
                            Spacer()
                            if let estimate = set.estimatedOneRepMax {
                                Text(estimate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let notes = entry.notes {
                        Text(notes).font(.footnote).foregroundStyle(.secondary)
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
