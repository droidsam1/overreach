import DesignSystem
import Domain
import SwiftUI
import TodayPresentation

/// The "Your week" card of Today (`docs/design/today-visual.md`, ADR-0042): the week strip and its progress, then
/// today's session. Without a week it shows only today's session rows in the same card style.
struct TodayWeekCard: View {
    let week: TodayWeek?
    let strength: ScheduledTrainingRow?
    let runs: [ScheduledTrainingRow]
    let openStrength: () -> Void
    let openRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            if let week {
                header(week)
                WeekStrip(days: week.days.map(Self.day))
                progress(week)
                if let session = week.session {
                    Divider()
                    sessionRow(
                        Row(kind: session.kind, title: session.title, detail: session.detail,
                            originalTitle: session.originalTitle, tag: session.tag),
                        action: session.kind == .run ? openRun : openStrength
                    )
                }
            } else {
                plainRows
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: HeroMetrics.radius))
    }

    /// Today's rows without the week: the planned strength session and runs.
    @ViewBuilder private var plainRows: some View {
        if let strength {
            sessionRow(Row(kind: .strength, title: strength.title, detail: strength.status), action: openStrength)
        }
        ForEach(runs) { run in
            sessionRow(Row(kind: .run, title: run.title, detail: run.status), action: openRun)
        }
    }

    private func header(_ week: TodayWeek) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your week").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            if let block = week.blockTitle {
                Text(verbatim: block).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }

    /// The bar and its summary are read once, as the summary; the days follow one by one.
    private func progress(_ week: TodayWeek) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ProgressBar(
                segments: [
                    .init(fraction: week.strengthSegment, color: WeekDayKind.strengthColor),
                    .init(fraction: week.runSegment, color: WeekDayKind.runColor),
                ],
                accessibilityLabel: week.summary, accessibilityValue: ""
            )
            .accessibilityHidden(true)
            Text(verbatim: week.summary).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private struct Row {
        let kind: TodayWeek.SessionKind
        let title: String
        let detail: String?
        var originalTitle: String?
        var tag: TodayWeek.SessionTag = .today
    }

    private func sessionRow(_ row: Row, action: @escaping () -> Void) -> some View {
        let (kind, title, detail, originalTitle, tag) = (row.kind, row.title, row.detail, row.originalTitle, row.tag)
        let color = kind == .run ? WeekDayKind.runColor : WeekDayKind.strengthColor
        return Button(action: action) {
            HStack(spacing: Spacing.small + Spacing.xSmall) {
                Image(systemName: kind == .run ? "figure.run" : "dumbbell.fill")
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.15), in: .rect(cornerRadius: Radius.card))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let originalTitle {
                        Text(verbatim: originalTitle).font(.caption).foregroundStyle(.secondary).strikethrough()
                    }
                    Text(verbatim: title).font(.headline)
                    if let detail {
                        Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Spacing.small)
                tagLabel(tag, color: color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func tagLabel(_ tag: TodayWeek.SessionTag, color: Color) -> some View {
        Group {
            switch tag {
            case .today: Text("Today")
            case .adjusted: Text("Adjusted")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
        .background(color.opacity(0.15), in: .capsule)
    }

    static func day(_ cell: TodayWeek.DayCell) -> WeekDay {
        let kind: WeekDayKind = switch cell.kind {
        case .strength, .both: .strengthDone
        case .run: .runDone
        case .restLogged: .restLogged
        case .planned: cell.isToday ? .today : .plannedStrength
        case .nothing: cell.isToday ? .today : .empty
        }
        return WeekDay(
            id: cell.id.hashValue, initial: cell.label, kind: kind, accessibilityLabel: cell.accessibilityLabel
        )
    }
}
