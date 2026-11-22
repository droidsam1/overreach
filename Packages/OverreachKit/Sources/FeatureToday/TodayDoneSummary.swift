import DesignSystem
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
                    totals(session)
                    ForEach(session.records, id: \.self) { record in
                        recordRow(record)
                    }
                }
            }
            if !done.tomorrow.isEmpty { tomorrow }
        }
    }

    @ViewBuilder private func totals(_ session: TodayDone.Session) -> some View {
        let values = Self.totals(session)
        if !values.isEmpty {
            HStack(spacing: Spacing.small) {
                ForEach(values, id: \.value) { total in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(total.label).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: total.value).font(.title3.weight(.heavy)).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.small + Spacing.xSmall)
                    .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.card))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func recordRow(_ record: String) -> some View {
        Label {
            Text(verbatim: record).font(.subheadline)
        } icon: {
            Image(systemName: "trophy.fill").foregroundStyle(tone.accent)
        }
        .padding(Spacing.small + Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.accent.opacity(0.12), in: .rect(cornerRadius: Radius.card))
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

    struct Total {
        let label: LocalizedStringKey
        let value: String
    }

    /// At most three: duration, then sets and volume for strength or distance and pace for a run.
    static func totals(_ session: TodayDone.Session) -> [Total] {
        var values: [Total] = []
        if let duration = session.duration { values.append(Total(label: "Duration", value: duration)) }
        if let sets = session.sets { values.append(Total(label: "Sets", value: String(sets))) }
        if let volume = session.volume { values.append(Total(label: "Volume", value: volume)) }
        if let distance = session.distance { values.append(Total(label: "Distance", value: distance)) }
        if let pace = session.pace { values.append(Total(label: "Pace", value: pace)) }
        return Array(values.prefix(3))
    }
}
