import DesignSystem
import Foundation
import PlanPresentation
import SwiftUI

// Views only: texts and the setting change come from `PlanModel` (ADR-0014).

/// Current stalled lifts, each with when it stopped progressing and one next step.
struct LiftsToUnblockSection: View {
    let model: PlanModel

    var body: some View {
        Section {
            ForEach(model.liftsToUnblockRows) { row in
                NavigationLink {
                    LiftToUnblockDetail(model: model, id: row.id)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(row.name).font(.headline)
                        Text(row.since).font(.subheadline).foregroundStyle(.secondary)
                        if let step = row.nextStep {
                            Text(step.text).font(.subheadline)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Lifts to unblock")
        } footer: {
            Text("Current lifts that stopped progressing. Each needs a change to that lift, not a deload.")
        }
    }
}

/// Why one lift is stalled, the next step with its evidence and, when it is a setting, a confirmed change.
private struct LiftToUnblockDetail: View {
    let model: PlanModel
    let id: UUID
    @State private var confirmsChange = false

    var body: some View {
        if let row = model.liftsToUnblockRows.first(where: { $0.id == id }) {
            Form {
                if let message = model.errorMessage {
                    InlineNotice(Text(message), tone: .critical)
                }
                Section {
                    Text(row.since)
                }
                if let step = row.nextStep {
                    Section("Next step") {
                        ExplainedLines(lines: [step])
                        if let change = row.change {
                            Button(change.title) { confirmsChange = true }
                                .disabled(model.isApplyingLiftChange)
                                .confirmationDialog(
                                    change.title, isPresented: $confirmsChange, titleVisibility: .visible
                                ) {
                                    Button("Apply") {
                                        Task { await model.applyNextStep(for: row.id) }
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text(change.confirmation)
                                }
                        }
                        if let note = row.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !row.otherSteps.isEmpty {
                    Section("Other options") {
                        ExplainedLines(lines: row.otherSteps)
                    }
                }
            }
            .navigationTitle(row.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView("No longer stalled", systemImage: "checkmark.circle")
        }
    }
}
