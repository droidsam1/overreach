import SwiftUI

/// One "Learn more" link: a reading behind an explanation (ADR-0027).
public struct ReadingLinkItem: Identifiable, Hashable {
    public let url: URL
    public let title: String
    /// e.g. "Fitness Revolucionario (Marcos Vázquez) · 2020 · in Spanish".
    public let detail: String
    /// A caveat, when the reading agrees with the app only in part.
    public let note: String?

    public var id: URL { url }

    public init(url: URL, title: String, detail: String, note: String? = nil) {
        self.url = url
        self.title = title
        self.detail = detail
        self.note = note
    }
}

/// A collapsed "Learn more" list under an explanation. Shows nothing without links. Links open in the browser.
public struct ReadingLinks: View {
    private let items: [ReadingLinkItem]

    public init(items: [ReadingLinkItem]) {
        self.items = items
    }

    public var body: some View {
        if !items.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(items) { item in
                        Link(destination: item.url) {
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(item.title).font(.footnote).multilineTextAlignment(.leading)
                                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                                if let note = item.note {
                                    Text(note).font(.caption2).foregroundStyle(.secondary).italic()
                                }
                            }
                        }
                        .accessibilityHint(Text("Opens in the browser"))
                    }
                }
                .padding(.top, Spacing.xSmall)
            } label: {
                Label("Learn more", systemImage: "book")
                    .font(.caption)
            }
        }
    }
}
