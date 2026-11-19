import DesignSystem
import SwiftUI
import WorkoutPresentation

// Views only: layout and styling. The numbers and texts come from `SessionSummary` (ADR-0014).

/// Shown after finishing a session: how it went against the plan, records and what comes next.
struct SessionSummaryView: View {
    let summary: SessionSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summary.headline).font(.headline.monospacedDigit())
                    if let adherence = summary.adherence {
                        Label(adherence, systemImage: "target")
                    }
                    if let comparison = summary.comparison {
                        Label(comparison, systemImage: "chart.line.uptrend.xyaxis")
                    }
                    if let muscles = summary.muscles {
                        Label(muscles, systemImage: "figure.strengthtraining.traditional")
                            .font(.footnote)
                    }
                }
                Section("Exercises") {
                    ForEach(summary.rows) { row in
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            Text(row.name).bold()
                            Label(row.outcomeText, systemImage: symbol(for: row.outcome))
                                .foregroundStyle(color(for: row.outcome))
                            ForEach(row.details, id: \.self) { detail in
                                Text(detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    ShareLink(item: summary.shareText) {
                        Label("Discuss it with an AI app", systemImage: "bubble.left.and.text.bubble.right")
                    }
                } footer: {
                    Text("Shares this summary as text. For a deeper analysis, share your full context from Plan → Ask AI.")
                }
            }
            .navigationTitle(summary.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func symbol(for outcome: SessionSummary.Outcome) -> String {
        switch outcome {
        case .above: "arrow.up.circle.fill"
        case .onTarget: "checkmark.circle.fill"
        case .below: "exclamationmark.triangle.fill"
        case .unfinished: "flag.fill"
        case .noTarget: "circle.dashed"
        }
    }

    private func color(for outcome: SessionSummary.Outcome) -> Color {
        switch outcome {
        case .above, .onTarget: .green
        case .below, .unfinished: .orange
        case .noTarget: .secondary
        }
    }
}
