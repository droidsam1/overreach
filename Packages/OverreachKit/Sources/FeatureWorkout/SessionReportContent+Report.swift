import DesignSystem
import PresentationKit

// Maps the shared report into the design system's display values.

extension SessionReportContent {
    /// The report right after finishing a session: it leads with the saved confirmation and the records.
    init(_ report: SessionReport) {
        self.init(
            title: report.title, headline: report.headline, adherence: report.adherence,
            comparison: report.comparison, muscles: report.muscles, achievements: report.achievements,
            isJustSaved: true,
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
