import SwiftUI

/// A row that stacks its content vertically at accessibility text sizes, where side by side it would not fit.
public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let verticalAlignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(
        verticalAlignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}

/// What an empty list shows: no results for the search, or that there is nothing yet.
public struct ListEmptyState: View {
    private let query: String
    private let title: LocalizedStringKey
    private let systemImage: String

    public init(query: String, title: LocalizedStringKey, systemImage: String) {
        self.query = query
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        if query.isEmpty {
            ContentUnavailableView(title, systemImage: systemImage)
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}
