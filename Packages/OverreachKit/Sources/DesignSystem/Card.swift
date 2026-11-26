import SwiftUI

/// A full-width surface for a related group of content.
public struct Card<Content: View>: View {
    private let surface: AnyShapeStyle
    private let border: Color
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(
        tone: StatusTone? = nil,
        radius: CGFloat = Radius.card,
        padding: CGFloat = Spacing.medium,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            surface: tone.map { AnyShapeStyle($0.surface) } ?? AnyShapeStyle(.background.secondary),
            border: tone?.border ?? .clear, radius: radius, padding: padding, content: content
        )
    }

    public init(
        surface: AnyShapeStyle,
        border: Color = .clear,
        radius: CGFloat = Radius.card,
        padding: CGFloat = Spacing.medium,
        @ViewBuilder content: () -> Content
    ) {
        self.surface = surface
        self.border = border
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: shape)
            .overlay {
                shape.stroke(border, lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// A readable heading with room for secondary text or an action.
public struct SectionHeader<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let title: Text
    private let font: Font
    private let trailing: Trailing

    public init(_ title: Text, font: Font = .headline, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.font = font
        self.trailing = trailing()
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    heading
                    trailing
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    heading
                    Spacer()
                    trailing.multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        title.font(font).accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    public init(_ title: Text, font: Font = .headline) {
        self.init(title, font: font) { EmptyView() }
    }
}

/// A decorative symbol with a tinted tile, used alongside a text description.
public struct IconTile: View {
    private let symbolName: String
    private let color: Color

    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 44

    public init(symbolName: String, color: Color) {
        self.symbolName = symbolName
        self.color = color
    }

    public var body: some View {
        Image(systemName: symbolName)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: .rect(cornerRadius: Radius.tile))
            .accessibilityHidden(true)
    }
}
