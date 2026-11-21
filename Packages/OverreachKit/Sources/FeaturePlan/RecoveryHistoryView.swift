import DesignSystem
import PlanPresentation
import SwiftUI

public struct RecoveryHistoryView: View {
    private let model: PlanModel

    public init(model: PlanModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if model.isAnalysing {
                ProgressView()
            } else if model.hasRecoveryHistory {
                RecoveryHistoryRows(model: model, showsDeloadHistory: true)
            } else {
                Text("No recovery periods recorded.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Recovery history")
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

    private func deloadDetails(_ row: DeloadRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(row.start...row.end)
            Text(row.reason.text).foregroundStyle(.secondary)
            Text(row.reason.evidence).font(.caption).foregroundStyle(.secondary)
        }
    }
}
