import SwiftUI

/// A tile with an icon over a label, for a grid of 3–4 shortcuts. It is only a label: wrap it in a
/// `Button` or a `NavigationLink`. At least 44 pt high. Display values only.
public struct LinkTile: View {
    private let title: LocalizedStringKey
    private let symbolName: String

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 72

    /// One neutral tint for every tile: the tiles are routes, not statuses, so they take no status tone, and the
    /// run, strength and sleep colours keep their one meaning (docs/design/today-visual.md).
    public static let iconColor = Color.accentColor

    public init(title: LocalizedStringKey, symbolName: String) {
        self.title = title
        self.symbolName = symbolName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Image(systemName: symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Self.iconColor)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: max(height, 44), alignment: .leading)
        .padding(Spacing.small + Spacing.xSmall)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.tile))
        .contentShape(.rect(cornerRadius: Radius.tile))
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
            Button {} label: { LinkTile(title: "Why", symbolName: "questionmark.circle") }
            Button {} label: { LinkTile(title: "Options", symbolName: "arrow.triangle.branch") }
            NavigationLink {} label: { LinkTile(title: "Recovery", symbolName: "bed.double.fill") }
            Button {} label: { LinkTile(title: "History", symbolName: "clock.fill") }
        }
        .buttonStyle(.plain)
        .padding()
    }
}
