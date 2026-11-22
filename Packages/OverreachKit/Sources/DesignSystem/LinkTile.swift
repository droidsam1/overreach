import SwiftUI

/// A tile with a coloured icon over a label, for a grid of 3–4 shortcuts. It is only a label: wrap it in a
/// `Button` or a `NavigationLink`. At least 44 pt high. Display values only.
public struct LinkTile: View {
    private let title: LocalizedStringKey
    private let symbolName: String
    private let color: Color

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 72

    public init(title: LocalizedStringKey, symbolName: String, color: Color) {
        self.title = title
        self.symbolName = symbolName
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Image(systemName: symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: max(height, 44), alignment: .leading)
        .padding(Spacing.small + Spacing.xSmall)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .contentShape(.rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Link tiles, light") {
    NavigationStack { LinkTileGrid() }.preferredColorScheme(.light)
}

#Preview("Link tiles, dark") {
    NavigationStack { LinkTileGrid() }.preferredColorScheme(.dark)
}

private struct LinkTileGrid: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: 4)) {
            Button {} label: { LinkTile(title: "Why", symbolName: "questionmark.circle", color: .orange) }
            Button {} label: { LinkTile(title: "Options", symbolName: "arrow.triangle.branch", color: .blue) }
            NavigationLink {} label: { LinkTile(title: "Recovery", symbolName: "bed.double.fill", color: .teal) }
            Button {} label: { LinkTile(title: "History", symbolName: "clock.fill", color: .purple) }
        }
        .buttonStyle(.plain)
        .padding()
    }
}
