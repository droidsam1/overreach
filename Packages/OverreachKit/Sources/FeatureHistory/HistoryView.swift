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
                        SessionDetail(session: summary.session, name: model.name(of:))
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

private struct SessionDetail: View {
    let session: StrengthSession
    let name: (UUID) -> String

    var body: some View {
        List {
            ForEach(session.entries) { entry in
                Section(name(entry.exerciseID)) {
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
        if set.kind == .warmup { parts.append("(warm-up)") }
        return parts.joined(separator: " ")
    }

    private func estimate(of set: WorkoutSet) -> Double? {
        guard set.isWorking, let weight = set.weightKg, let reps = set.reps else { return nil }
        return LoadPrescription.estimatedOneRepMax(weightKg: weight, reps: reps, rpe: set.rpe)
    }
}
