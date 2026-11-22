import DesignSystem
import Domain
import PresentationKit
import SwiftUI
import TodayPresentation

/// Level 2 of Today: what weighs on the verdict, a card per reason with a signal, the signals in range and rows to the
/// details (`docs/design/today-visual.md`, ADR-0042). It only draws `model.why`; `extra` holds the running advice,
/// deload and movement cards that already live on this screen, drawn in the same style.
struct TodayWhyView<Extra: View>: View {
    let model: TodayModel
    @ViewBuilder let extra: Extra

    var body: some View {
        let why = model.why
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                if let safety = why.safetyText {
                    Label(safety, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StatusTone.critical.accent)
                        .whyCard(tone: .critical)
                }
                if !why.weights.isEmpty { weighing(why) }
                ForEach(why.cards) { card in reasonCard(card) }
                if !why.normal.isEmpty { normalSignals(why) }
                extra
                if !why.rows.isEmpty { rows(why) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
        }
        .navigationTitle(model.whyTitle)
        .inlineNavigationTitle()
    }

    // MARK: What weighs

    private func weighing(_ why: TodayWhy) -> some View {
        let total = Double(why.weights.map(\.weight).reduce(0, +) + why.normalWeight)
        var segments = why.weights.map {
            ProgressBar.Segment(fraction: Double($0.weight) / total, color: $0.tone.tone.accent)
        }
        if why.normalWeight > 0 {
            segments.append(.init(fraction: Double(why.normalWeight) / total, color: StatusTone.positive.accent))
        }
        let inRange = L10n.text("In your range")
        let legend = why.weights.map(\.title) + (why.normalWeight > 0 ? [inRange] : [])
        return VStack(alignment: .leading, spacing: Spacing.small) {
            Text("What weighs").font(.headline).accessibilityAddTraits(.isHeader)
            ProgressBar(
                segments: segments, accessibilityLabel: L10n.text("What weighs"),
                accessibilityValue: legend.joined(separator: ", ")
            )
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                ForEach(why.weights) { weight in
                    legendRow(weight.title, color: weight.tone.tone.accent)
                }
                if why.normalWeight > 0 { legendRow(inRange, color: StatusTone.positive.accent) }
            }
            .accessibilityHidden(true)
        }
        .whyCard()
    }

    private func legendRow(_ title: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(verbatim: title).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Reasons

    private func reasonCard(_ card: TodayWhy.Card) -> some View {
        let signal = card.signal
        let tone = signal.tone.tone
        return VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: signal.title).font(.headline)
                Spacer()
                Text(verbatim: signal.value).font(.title3.weight(.heavy))
                if !signal.unit.isEmpty {
                    Text(verbatim: signal.unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if let value = card.gaugeValue {
                RangeGauge(
                    value: value, scale: 0...2, usual: 0.8...1.3, tone: tone,
                    accessibilityLabel: spoken(signal)
                )
            } else {
                SignalTrendChart(
                    values: signal.trend, band: signal.band, tone: tone, size: .full,
                    startLabel: L10n.text("14 days ago"), endLabel: L10n.text("Today"), summary: spoken(signal)
                )
            }
            Text(verbatim: card.sentence).font(.subheadline)
            if !card.evidence.isEmpty { evidence(card) }
        }
        .whyCard(tone: tone)
    }

    /// What VoiceOver reads for the chart or gauge: the signal, how it compares and the span of the trend.
    private func spoken(_ signal: TodaySignal) -> String {
        let value = "\(signal.value) \(signal.unit)".trimmingCharacters(in: .whitespaces)
        return L10n.format("{1}, {2}, {3}. Trend over the last 14 days.", signal.title, value, signal.status)
    }

    private func evidence(_ card: TodayWhy.Card) -> some View {
        HStack(spacing: Spacing.small) {
            Text(verbatim: card.evidence)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.xSmall)
                .background(Color.secondary.opacity(0.18), in: .capsule)
            if let source = card.source {
                Link("Research source", destination: source).font(.caption)
            }
        }
    }

    // MARK: In range

    private func normalSignals(_ why: TodayWhy) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("In your range").font(.headline).accessibilityAddTraits(.isHeader)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.small)], spacing: Spacing.small
            ) {
                ForEach(why.normal) { normal in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(verbatim: normal.title).font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(verbatim: normal.value).font(.title3.weight(.heavy))
                            Text(verbatim: normal.unit).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(verbatim: normal.baseline).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.small + Spacing.xSmall)
                    .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.card))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Rows

    private func rows(_ why: TodayWhy) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(why.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                NavigationLink {
                    detail(row)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            Text(verbatim: row.title).font(.body.weight(.semibold))
                            Text(verbatim: row.detail).font(.footnote).foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, Spacing.small)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xSmall)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.card))
    }

    private func detail(_ row: TodayWhy.Row) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                switch row.kind {
                case .trainingThatCounts: trainingThatCounts
                case .sourcesAndCoverage: sourcesAndCoverage
                case .furtherReading: furtherReading
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
        }
        .navigationTitle(row.title)
        .inlineNavigationTitle()
    }

    @ViewBuilder private var trainingThatCounts: some View {
        if let context = model.readinessTrainingContext {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(verbatim: context.heading).font(.headline)
                ForEach(context.workouts, id: \.self) { Text(verbatim: $0).font(.subheadline) }
            }
            .whyCard()
        }
    }

    @ViewBuilder private var sourcesAndCoverage: some View {
        if let note = model.hrvCoverageNote {
            Text(verbatim: note).font(.subheadline).foregroundStyle(.secondary).whyCard()
        }
        ForEach(model.readinessSources) { source in
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(verbatim: source.title).font(.subheadline.weight(.semibold))
                ForEach(source.details, id: \.self) {
                    Text(verbatim: $0).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .whyCard()
        }
    }

    /// The readings behind the reasons, each once, in the order the reasons are listed.
    private var readings: [ReadingLinkItem] {
        var seen = Set<Reading>()
        return model.readinessLines.flatMap(\.readings).filter { seen.insert($0).inserted }
            .map(ReadingLinkItem.init)
    }

    @ViewBuilder private var furtherReading: some View {
        ForEach(readings) { item in
            Link(destination: item.url) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(verbatim: item.title).font(.subheadline.weight(.semibold))
                    Text(verbatim: item.detail).font(.footnote).foregroundStyle(.secondary)
                    if let note = item.note { Text(verbatim: note).font(.footnote).foregroundStyle(.secondary) }
                }
                .multilineTextAlignment(.leading)
            }
            .whyCard()
        }
    }
}

private extension View {
    /// The card style of the Why screen: the neutral tile, or an accent border for a reason.
    func whyCard(tone: StatusTone = .neutral) -> some View {
        padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.card))
            .overlay {
                if tone != .neutral {
                    RoundedRectangle(cornerRadius: Radius.card).stroke(tone.accent.opacity(0.6), lineWidth: 1)
                }
            }
    }

    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
