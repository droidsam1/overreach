import DesignSystem
import Foundation
import PlanPresentation
import SwiftUI

// Views only: texts and the setting change come from `PlanModel` (ADR-0014).

/// Current stalled lifts, each with when it stopped progressing and one next step.
struct LiftsToUnblockSection: View {
    let model: PlanModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SectionHeader(Text("Lifts to unblock"))
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
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
                Text("Current lifts that stopped progressing. Each needs a change to that lift, not a deload.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    if let message = model.errorMessage {
                        InlineNotice(Text(message), tone: .critical)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            Text(row.since).font(.headline)
                            if let step = row.nextStep {
                                SectionHeader(Text("Next step"))
                                ExplainedLines(lines: [step])
                                nextStepAction(row)
                                if let note = row.note {
                                    Text(note).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !row.otherSteps.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.small) {
                                SectionHeader(Text("Other options"))
                                ExplainedLines(lines: row.otherSteps)
                            }
                        }
                    }
                }
                .padding(Spacing.medium)
            }
            .navigationTitle(row.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView("No longer stalled", systemImage: "checkmark.circle")
        }
    }

    @ViewBuilder private func nextStepAction(_ row: LiftToUnblockRow) -> some View {
        if let change = row.change {
            Button(change.title) { confirmsChange = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.isApplyingLiftChange)
                .confirmationDialog(change.title, isPresented: $confirmsChange, titleVisibility: .visible) {
                    Button("Apply") { Task { await model.applyNextStep(for: row.id) } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(change.confirmation)
                }
        }
    }
}
