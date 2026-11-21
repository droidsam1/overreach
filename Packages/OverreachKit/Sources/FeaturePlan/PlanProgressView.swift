import DesignSystem
import PlanPresentation
import SwiftUI

/// Progress in "Recovery & Progress": the last recovery periods, lifts that stopped progressing and the linked
/// running results. Shown from the Recovery tab, from Plan's "View progress" and from Today's deload explanation.
public struct PlanProgressView: View {
    private let model: PlanModel

    public init(model: PlanModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if model.isAnalysing {
                ProgressView("Loading…")
            } else if !model.hasProgress {
                Section {
                    Text("No progress yet. Log workouts or link runs to see recovery periods, stalled lifts and goal results.")
                        .foregroundStyle(.secondary)
                }
            }
            if model.hasRecoveryHistory {
                Section("Recovery periods") {
                    RecoveryHistoryRows(model: model, showsDeloadHistory: true)
                }
            }
            if !model.liftsToUnblockRows.isEmpty { LiftsToUnblockSection(model: model) }
            if let progress = model.runningGoalProgress {
                Section("Running goal") {
                    NavigationLink {
                        RunningGoalProgressView(model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            Text(progress.goal).font(.headline)
                            Text(progress.status).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Progress")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct RecoveryHistoryRows: View {
    let model: PlanModel
    @State var showsDeloadHistory = false

    var body: some View {
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
            deloadQuestion(row)
        }
        if !model.olderDeloadRows.isEmpty {
            DisclosureGroup("Older periods") {
                ForEach(model.olderDeloadRows) { row in
                    deloadQuestion(row)
                }
            }
        }
    }

    private func deloadQuestion(_ row: DeloadQuestionRow) -> some View {
        DeloadQuestionView(model: model, row: row)
    }

    private func deloadDetails(_ row: DeloadRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(row.start...row.end)
            Text(row.reason.text).foregroundStyle(.secondary)
            Text(row.reason.evidence).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// "Was this a rest period?" with its details and the two answers. Shown in Plan beside the block decision it
/// affects and in Progress with the other recovery periods.
struct DeloadQuestionView: View {
    let model: PlanModel
    let row: DeloadQuestionRow

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Was this a rest period?").font(.headline)
            Text(row.details.dates)
            if let strength = row.details.strength { Text(strength) }
            if let running = row.details.running { Text(running) }
            Text(row.details.reason).font(.footnote).foregroundStyle(.secondary)
            Button("Yes, it was rest") {
                Task { await model.reviewDeload(id: row.id, accepted: true) }
            }
            Button("No") {
                Task { await model.reviewDeload(id: row.id, accepted: false) }
            }
        }
        .buttonStyle(.borderless)
        .disabled(model.isReviewingDeload)
    }
}
