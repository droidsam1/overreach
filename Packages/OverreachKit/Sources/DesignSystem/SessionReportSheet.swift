import SwiftUI

/// What `SessionReportSheet` shows, as display values (the features map their report into it).
public struct SessionReportContent: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case above, onTarget, below, unfinished, noTarget
    }

    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        public let outcome: Outcome
        public let outcomeText: String
        public let details: [String]

        public init(id: UUID, name: String, outcome: Outcome, outcomeText: String, details: [String]) {
            self.id = id
            self.name = name
            self.outcome = outcome
            self.outcomeText = outcomeText
            self.details = details
        }
    }

    public let title: String
    public let headline: String
    public let totals: [SummaryMetric]
    public let adherence: String?
    public let comparison: String?
    public let muscles: String?
    /// Real records of the session, shown first; never a streak, points or a badge.
    public let achievements: [String]
    /// Shown right after finishing: the sheet leads with the confirmation that the session was saved.
    public let isJustSaved: Bool
    public let rows: [Row]
    public let shareText: String

    public init(
        title: String, headline: String, adherence: String?, comparison: String?, muscles: String?,
        totals: [SummaryMetric] = [], achievements: [String] = [], isJustSaved: Bool = false,
        rows: [Row], shareText: String
    ) {
        self.title = title
        self.headline = headline
        self.totals = totals
        self.adherence = adherence
        self.comparison = comparison
        self.muscles = muscles
        self.achievements = achievements
        self.isJustSaved = isJustSaved
        self.rows = rows
        self.shareText = shareText
    }
}

/// How a session went: against the plan, records and what comes next. After finishing it, or from History.
public struct SessionReportSheet: View {
    private let content: SessionReportContent
    @Environment(\.dismiss) private var dismiss

    public init(content: SessionReportContent) {
        self.content = content
    }

    public var body: some View {
        NavigationStack {
            List {
                summary
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                Section("Exercises") {
                    ForEach(content.rows) { row in
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
                    ShareLink(item: content.shareText) {
                        Label("Discuss it with an AI app", systemImage: "bubble.left.and.text.bubble.right")
                    }
                } footer: {
                    Text("Shares this summary as text. For a deeper analysis, share your full context from Plan → Ask AI.")
                }
            }
            .navigationTitle(content.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        Card(tone: content.isJustSaved ? .done : nil) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                if content.isJustSaved {
                    AdaptiveStack(spacing: Spacing.medium) {
                        ReadinessRing(tone: .done, size: 54, accessibilityLabel: "")
                            .accessibilityHidden(true)
                        SectionHeader(Text("Workout saved to History"), font: .title2.weight(.bold))
                    }
                }
                if content.totals.isEmpty {
                    Text(content.headline).font(.headline.monospacedDigit())
                } else {
                    SummaryTiles(content.totals)
                }
                ForEach(content.achievements, id: \.self) { achievement in
                    TrainingRecordRow(achievement)
                }
                if let adherence = content.adherence {
                    Label(adherence, systemImage: "target")
                }
                if let comparison = content.comparison {
                    Label(comparison, systemImage: "chart.line.uptrend.xyaxis")
                }
                if let muscles = content.muscles {
                    Label(muscles, systemImage: "figure.strengthtraining.traditional")
                        .font(.footnote)
                }
            }
        }
    }

    private func symbol(for outcome: SessionReportContent.Outcome) -> String {
        switch outcome {
        case .above: "arrow.up.circle.fill"
        case .onTarget: "checkmark.circle.fill"
        case .below: "exclamationmark.triangle.fill"
        case .unfinished: "flag.fill"
        case .noTarget: "circle.dashed"
        }
    }

    private func color(for outcome: SessionReportContent.Outcome) -> Color {
        switch outcome {
        case .above, .onTarget: StatusTone.positive.accent
        case .below, .unfinished: StatusTone.caution.accent
        case .noTarget: .secondary
        }
    }
}
