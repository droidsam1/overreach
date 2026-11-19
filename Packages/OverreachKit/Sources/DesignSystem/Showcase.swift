import SwiftUI

/// A slowly moving tinted gradient for welcome-style screens. Still when Reduce Motion is on.
public struct AnimatedBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            Rectangle().fill(.background)
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                mesh(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func mesh(at time: TimeInterval) -> some View {
        let centerX = Float(0.5 + 0.15 * sin(time * 0.45))
        let centerY = Float(0.5 + 0.15 * cos(time * 0.35))
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [centerX, centerY], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .accentColor.opacity(0.35), .accentColor.opacity(0.12), .clear,
                .accentColor.opacity(0.08), .accentColor.opacity(0.25), .accentColor.opacity(0.05),
                .clear, .accentColor.opacity(0.1), .accentColor.opacity(0.3),
            ]
        )
    }
}

/// A feature or novelty: tinted symbol, title and a short detail.
public struct FeatureHighlightRow: View {
    private let symbol: String
    private let title: Text
    private let detail: Text?

    public init(symbol: String, title: Text, detail: Text? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline)
                if let detail {
                    detail.font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Page dots: the current page is wider and tinted.
public struct PageDots: View {
    private let count: Int
    private let index: Int

    public init(count: Int, index: Int) {
        self.count = count
        self.index = index
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { page in
                Capsule()
                    .fill(page == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.4)))
                    .frame(width: page == index ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.4), value: index)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
    }
}
