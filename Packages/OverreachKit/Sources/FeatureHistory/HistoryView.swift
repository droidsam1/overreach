import Analytics
import DesignSystem
import Domain
import SwiftUI

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
                        SessionDetail(model: model, sessionID: summary.id)
                    } label: {
                        SessionRow(summary: summary)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.summaries[$0].id }
                    Task {
                        for id in ids { await model.delete(id) }
                    }
                }
            }
            .overlay {
                if model.summaries.isEmpty && !model.isLoading && model.errorMessage == nil {
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
                Text(summary.session.name).font(.headline)
                Spacer()
                Text(summary.session.startedAt, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(summary.exerciseNames.joined(separator: ", "))
                .font(.subheadline)
                .lineLimit(2)
            Text("\(summary.workingSets) sets · \(summary.tonnageKg.formatted(.number.precision(.fractionLength(0)))) kg")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// One session's sets, with an Edit button. Reads the session from the model so it reflects saved edits.
private struct SessionDetail: View {
    let model: HistoryModel
    let sessionID: UUID
    @State private var editor: SessionEditorModel?

    var body: some View {
        if let session = model.session(id: sessionID) {
            content(session)
                .toolbar {
                    Button("Edit") { editor = model.makeEditor(for: session) }
                }
                .sheet(item: $editor) { editor in
                    SessionEditorView(model: editor) { model.didSave($0) }
                }
        } else {
            ContentUnavailableView("Session not found", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func content(_ session: StrengthSession) -> some View {
        List {
            SessionInfo(session: session)
            ForEach(session.entries) { entry in
                Section(model.name(of: entry.exerciseID)) {
                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("\(index + 1)").foregroundStyle(.secondary)
                            Text(describe(set)).monospacedDigit()
                            Spacer()
                            if let estimate = estimate(of: set) {
                                Text("e1RM \(estimate.formatted(.number.precision(.fractionLength(1))))")
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
        .navigationTitle(session.name)
    }

    private func describe(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        if let weight = set.weightKg { parts.append("\(weight.formatted()) kg") }
        if let reps = set.reps { parts.append("× \(reps)") }
        if let rpe = set.rpe { parts.append("@ \(rpe.formatted())") }
        switch set.kind {
        case .warmup: parts.append("(warm-up)")
        case .dropSet: parts.append("(drop set)")
        case .failure: parts.append("(failure)")
        case .working: break
        }
        return parts.joined(separator: " ")
    }

    private func estimate(of set: WorkoutSet) -> Double? {
        guard set.isWorking, let weight = set.weightKg, let reps = set.reps else { return nil }
        return LoadPrescription.estimatedOneRepMax(weightKg: weight, reps: reps, rpe: set.rpe)
    }
}

/// Date, duration, focus and notes of a session.
private struct SessionInfo: View {
    let session: StrengthSession

    var body: some View {
        Section {
            LabeledContent("Date") {
                Text(session.startedAt, format: .dateTime.weekday().day().month().year().hour().minute())
            }
            if let duration = session.durationSeconds {
                LabeledContent("Duration") {
                    Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                }
            }
            if let focus = session.focus {
                LabeledContent("Focus", value: focus.title)
            }
            if let notes = session.notes {
                Text(notes).font(.callout)
            }
        }
    }
}
