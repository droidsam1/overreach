import DesignSystem
import PresentationKit

// Maps the shared report into the design system's display values.

extension SessionReportContent {
    init(_ report: SessionReport) {
        let totals = [
            report.duration.map { SummaryMetric(label: L10n.text("Duration"), value: $0) },
            report.workingSets.map { SummaryMetric(label: L10n.text("Sets"), value: String($0)) },
            report.volume.map { SummaryMetric(label: L10n.text("Volume"), value: $0) }
        ].compactMap { $0 }
        self.init(
            title: report.title, headline: report.headline, adherence: report.adherence,
            comparison: report.comparison, muscles: report.muscles, totals: totals,
            rows: report.rows.map { row in
                Row(id: row.id, name: row.name, outcome: Outcome(row.outcome), outcomeText: row.outcomeText,
                    details: row.details)
            },
            shareText: report.shareText
        )
    }
}

extension SessionReportContent.Outcome {
    init(_ outcome: SessionReport.Outcome) {
        switch outcome {
        case .above: self = .above
        case .onTarget: self = .onTarget
        case .below: self = .below
        case .unfinished: self = .unfinished
        case .noTarget: self = .noTarget
        }
    }
}
