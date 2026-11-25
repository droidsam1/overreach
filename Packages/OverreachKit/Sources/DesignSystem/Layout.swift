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

/// Set number and trailing action stay together when the editable values need their own row.
public struct SetEntryRow<Fields: View, Action: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let number: SetNumberLabel
    private let fields: Fields
    private let action: Action

    public init(
        number: SetNumberLabel,
        @ViewBuilder fields: () -> Fields,
        @ViewBuilder action: () -> Action
    ) {
        self.number = number
        self.fields = fields()
        self.action = action()
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            expanded
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) {
                    number
                    fields.fixedSize(horizontal: true, vertical: false)
                    action
                }
                expanded
            }
        }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack {
                number
                Spacer(minLength: Spacing.small)
                action
            }
            fields
        }
    }
}

/// What an empty list shows: no results for the search, or that there is nothing yet.
public struct ListEmptyState: View {
    private let query: String
    private let title: LocalizedStringKey
    private let systemImage: String
    private let description: Text?

    public init(
        query: String = "", title: LocalizedStringKey, systemImage: String, description: Text? = nil
    ) {
        self.query = query
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    public var body: some View {
        if query.isEmpty {
            ContentUnavailableView(title, systemImage: systemImage, description: description)
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}
