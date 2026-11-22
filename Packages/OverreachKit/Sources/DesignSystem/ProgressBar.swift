import SwiftUI

/// A rounded bar with coloured segments over a track, such as strength and run sessions of the week.
/// Display values only; the caller supplies the spoken value ("4 of 6").
public struct ProgressBar: View {
    public struct Segment: Sendable {
        public let fraction: Double
        public let color: Color

        public init(fraction: Double, color: Color) {
            self.fraction = fraction
            self.color = color
        }
    }

    private let segments: [Segment]
    private let accessibilityText: String
    private let accessibilityValueText: String
    private let height: CGFloat

    public init(
        segments: [Segment], height: CGFloat = 10, accessibilityLabel: String, accessibilityValue: String
    ) {
        self.segments = segments
        self.height = height
        self.accessibilityText = accessibilityLabel
        self.accessibilityValueText = accessibilityValue
    }

    public var body: some View {
        GeometryReader { proxy in
            let widths = Self.widths(segments.map(\.fraction), total: proxy.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        Rectangle().fill(segment.color).frame(width: widths[index])
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(accessibilityValueText)
    }

    /// Widths of the segments, clamped so they never exceed the track.
    static func widths(_ fractions: [Double], total: CGFloat) -> [CGFloat] {
        var left = 1.0
        return fractions.map { raw in
            let part = min(max(raw, 0), left)
            left -= part
            return total * part
        }
    }
}

#Preview("Progress") {
    VStack(spacing: 16) {
        ProgressBar(
            segments: [.init(fraction: 0.33, color: .purple), .init(fraction: 0.33, color: .blue)],
            accessibilityLabel: "Week", accessibilityValue: "4 of 6")
        ProgressBar(segments: [], accessibilityLabel: "Week", accessibilityValue: "0 of 6")
    }
    .padding()
}
