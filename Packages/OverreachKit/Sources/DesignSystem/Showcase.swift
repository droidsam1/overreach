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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: index)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
    }
}

/// A large tappable choice: symbol, title and detail. Selected cards fill with the tint, grow a little and show a
/// check, with a springy animation; VoiceOver reads them as selectable buttons.
public struct ChoiceCard: View {
    private let symbol: String
    private let title: Text
    private let detail: Text?
    private let isSelected: Bool
    private let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(symbol: String, title: Text, detail: Text? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.medium) {
                Image(systemName: symbol)
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.12)))
                    )
                    .symbolEffect(.bounce, value: isSelected)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.headline).foregroundStyle(.primary)
                    if let detail {
                        detail.font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            )
            .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.4), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
