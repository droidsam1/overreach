import SwiftUI

/// A ring showing a 0…1 fraction in the tone's accent over a dimmed track, with the tone's symbol in the centre.
/// The caller supplies the VoiceOver label (for example "Readiness: green"). Display values only.
public struct ReadinessRing: View {
    private let tone: StatusTone
    private let fraction: Double
    private let accessibilityText: String
    private let size: CGFloat

    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    public init(tone: StatusTone, fraction: Double = 1, size: CGFloat = 88, accessibilityLabel: String) {
        self.tone = tone
        self.fraction = min(max(fraction, 0), 1)
        self.size = size
        self.accessibilityText = accessibilityLabel
    }

    public var body: some View {
        let side = min(size * scale, size * 1.6)
        let line = side * 0.12
        ZStack {
            Circle().stroke(tone.accent.opacity(0.25), lineWidth: line)
            Circle()
                .trim(from: 0, to: shown || reduceMotion ? fraction : 0)
                .stroke(tone.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: tone.ringGlyph)
                .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(tone.accent)
        }
        .frame(width: side, height: side)
        .padding(line / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.6)) { shown = true }
        }
    }
}

#Preview("Tones, light") {
    HStack {
        ForEach(StatusTone.allCases, id: \.self) {
            ReadinessRing(tone: $0, fraction: 0.8, accessibilityLabel: "Ring")
        }
    }
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Tones, dark") {
    HStack {
        ForEach(StatusTone.allCases, id: \.self) {
            ReadinessRing(tone: $0, fraction: 0.8, accessibilityLabel: "Ring")
        }
    }
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility size") {
    ReadinessRing(tone: .caution, fraction: 0.5, accessibilityLabel: "Readiness: amber")
        .padding()
        .environment(\.dynamicTypeSize, .accessibility3)
}
