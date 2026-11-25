import SwiftUI

/// A localized label and its display-ready value.
public struct SummaryMetric: Hashable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// The headline results of a session. Tiles stack at accessibility sizes.
public struct SummaryTiles: View {
    private let metrics: [SummaryMetric]

    public init(_ metrics: [SummaryMetric]) {
        self.metrics = metrics
    }

    public var body: some View {
        if !metrics.isEmpty {
            AdaptiveStack(verticalAlignment: .top, spacing: Spacing.small) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                    Card(
                        surface: AnyShapeStyle(Color.secondary.opacity(0.12)), radius: Radius.tile,
                        padding: Spacing.small + Spacing.xSmall
                    ) {
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            Text(verbatim: metric.label).font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: metric.value).font(.title3.weight(.heavy)).minimumScaleFactor(0.7)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A record achieved in the session, with a trophy and the caller's tone.
public struct TrainingRecordRow: View {
    private let record: String
    private let tone: StatusTone

    public init(_ record: String, tone: StatusTone = .done) {
        self.record = record
        self.tone = tone
    }

    public var body: some View {
        Card(
            surface: AnyShapeStyle(tone.accent.opacity(0.12)), radius: Radius.tile,
            padding: Spacing.small + Spacing.xSmall
        ) {
            Label {
                Text(verbatim: record).font(.subheadline)
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(tone.accent).accessibilityHidden(true)
            }
        }
    }
}
