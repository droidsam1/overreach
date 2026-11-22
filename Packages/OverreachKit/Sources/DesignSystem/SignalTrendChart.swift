import Charts
import SwiftUI

/// A small line or bar chart of optional values (gaps allowed) over an optional shaded band, with the points
/// outside the band in the tone's accent. Display values only. Fewer than two values draw nothing.
public struct SignalTrendChart: View {
    public enum Style: Sendable { case line, bars }
    public enum Size: Sendable { case compact, full }

    private let values: [Double?]
    private let band: ClosedRange<Double>?
    private let tone: StatusTone
    private let style: Style
    private let size: Size
    private let startLabel: String?
    private let endLabel: String?
    private let summary: String?

    /// `summary` is read by VoiceOver in full size; compact charts are hidden because the tile says the status.
    public init(
        values: [Double?], band: ClosedRange<Double>? = nil, tone: StatusTone = .neutral, style: Style = .line,
        size: Size = .compact, startLabel: String? = nil, endLabel: String? = nil, summary: String? = nil
    ) {
        self.values = values
        self.band = band
        self.tone = tone
        self.style = style
        self.size = size
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.summary = summary
    }

    /// Whether there is enough data to draw (ADR-0041: no empty charts).
    public static func hasData(_ values: [Double?]) -> Bool {
        values.compactMap { $0 }.count >= 2
    }

    private var points: [(index: Int, value: Double)] {
        values.enumerated().compactMap { index, value in value.map { (index, $0) } }
    }

    private func isOutside(_ value: Double) -> Bool {
        guard let band else { return false }
        return !band.contains(value)
    }

    public var body: some View {
        if Self.hasData(values) {
            VStack(spacing: Spacing.xSmall) {
                chart
                    .frame(width: size == .compact ? 90 : nil, height: size == .compact ? 18 : 96)
                if size == .full, startLabel != nil || endLabel != nil {
                    HStack {
                        Text(verbatim: startLabel ?? "")
                        Spacer()
                        Text(verbatim: endLabel ?? "")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(size == .full ? summary ?? "" : "")
            .accessibilityHidden(size == .compact || summary == nil)
        }
    }

    private var chart: some View {
        Chart {
            if let band {
                RectangleMark(
                    xStart: .value("Start", 0), xEnd: .value("End", max(values.count - 1, 1)),
                    yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound)
                )
                .foregroundStyle(Color.secondary.opacity(0.18))
            }
            ForEach(points, id: \.index) { point in
                switch style {
                case .line:
                    LineMark(x: .value("Day", point.index), y: .value("Value", point.value))
                        .foregroundStyle(Color.secondary)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", point.index), y: .value("Value", point.value))
                        .symbolSize(isOutside(point.value) ? 40 : 10)
                        .foregroundStyle(isOutside(point.value) ? tone.accent : Color.secondary)
                case .bars:
                    BarMark(x: .value("Day", point.index), y: .value("Value", point.value))
                        .foregroundStyle(isOutside(point.value) ? tone.accent : Color.secondary)
                }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
    }

    private var yDomain: ClosedRange<Double> {
        let all = points.map(\.value) + [band?.lowerBound, band?.upperBound].compactMap { $0 }
        let low = all.min() ?? 0
        let high = all.max() ?? 1
        let pad = max((high - low) * 0.1, 0.001)
        return (style == .bars ? min(0, low) : low - pad)...(high + pad)
    }
}

#Preview("In band") {
    SignalTrendChart(values: [50, 52, 49, 51, 53, 50, 52], band: 46...56, tone: .positive)
        .padding()
}

#Preview("Below band, full, dark") {
    SignalTrendChart(
        values: [50, 52, 49, 41, 38, 36, 34], band: 46...56, tone: .caution, size: .full,
        startLabel: "14 d", endLabel: "Today", summary: "Falling below your usual range"
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Gaps") {
    SignalTrendChart(values: [50, nil, 49, nil, nil, 53, 52], band: 46...56, tone: .caution)
        .padding()
}

#Preview("Empty and single point") {
    VStack {
        SignalTrendChart(values: [])
        SignalTrendChart(values: [nil, 50, nil])
    }
    .padding()
}
