import DesignSystem
import PresentationKit
import SwiftUI
import TodayPresentation

/// What the hero shows once today is done: the totals of each session, the records it set and tomorrow's session
/// (`docs/design/today-visual.md`, "After training"). Rest logged has only tomorrow.
struct TodayDoneSummary: View {
    let done: TodayDone
    let tone: StatusTone

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            ForEach(done.sessions) { session in
                VStack(alignment: .leading, spacing: Spacing.small) {
                    if done.sessions.count > 1 {
                        Text(verbatim: session.title).font(.subheadline.weight(.semibold))
                    }
                    SummaryTiles(Self.totals(session))
                    ForEach(session.records, id: \.self) { record in
                        TrainingRecordRow(record, tone: tone)
                    }
                }
            }
            if !done.tomorrow.isEmpty { tomorrow }
        }
    }

    private var tomorrow: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Tomorrow").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(done.tomorrow.enumerated()), id: \.offset) { _, next in
                Text(verbatim: [next.title, next.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// At most three: duration, then sets and volume for strength or distance and pace for a run.
    static func totals(_ session: TodayDone.Session) -> [SummaryMetric] {
        var values: [SummaryMetric] = []
        if let duration = session.duration { values.append(.init(label: L10n.text("Duration"), value: duration)) }
        if let sets = session.sets { values.append(.init(label: L10n.text("Sets"), value: String(sets))) }
        if let volume = session.volume { values.append(.init(label: L10n.text("Volume"), value: volume)) }
        if let distance = session.distance { values.append(.init(label: L10n.text("Distance"), value: distance)) }
        if let pace = session.pace { values.append(.init(label: L10n.text("Pace"), value: pace)) }
        return Array(values.prefix(3))
    }
}
