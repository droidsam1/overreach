import SwiftUI

/// A horizontal track with a shaded "usual" zone and a marker, such as ACWR against its usual range.
/// Values are in the gauge's own units; the caller supplies the spoken description. Display values only.
public struct RangeGauge: View {
    private let value: Double
    private let scale: ClosedRange<Double>
    private let usual: ClosedRange<Double>
    private let tone: StatusTone
    private let accessibilityText: String

    public init(
        value: Double, scale: ClosedRange<Double>, usual: ClosedRange<Double>, tone: StatusTone = .neutral,
        accessibilityLabel: String
    ) {
        self.value = value
        self.scale = scale
        self.usual = usual
        self.tone = tone
        self.accessibilityText = accessibilityLabel
    }

    /// Position of `x` on the track, 0…1.
    static func position(_ point: Double, in scale: ClosedRange<Double>) -> Double {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0 }
        return min(max((point - scale.lowerBound) / span, 0), 1)
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let low = Self.position(usual.lowerBound, in: scale) * width
            let high = Self.position(usual.upperBound, in: scale) * width
            let marker = Self.position(value, in: scale) * width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 8)
                Capsule().fill(StatusTone.positive.accent.opacity(0.35))
                    .frame(width: max(high - low, 0), height: 8)
                    .offset(x: low)
                Circle().fill(tone.accent)
                    .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1))
                    .frame(width: 16, height: 16)
                    .offset(x: min(max(marker - 8, 0), width - 16))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

#Preview("Gauge") {
    VStack(spacing: 24) {
        RangeGauge(value: 1.0, scale: 0...2, usual: 0.8...1.3, tone: .positive, accessibilityLabel: "Load")
        RangeGauge(value: 1.7, scale: 0...2, usual: 0.8...1.3, tone: .critical, accessibilityLabel: "Load")
    }
    .padding()
    .preferredColorScheme(.dark)
}
