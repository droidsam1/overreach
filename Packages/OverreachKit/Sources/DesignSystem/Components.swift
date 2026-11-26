import SwiftUI

/// Uses readable system text and a separate semantic symbol.
public struct StatusLabel: View {
    private let title: String
    private let tone: StatusTone

    public init(title: String, tone: StatusTone) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
        }
    }
}

/// A tinted badge for a semantic status, such as a readiness level.
public struct StatusBadge: View {
    private let title: String
    private let tone: StatusTone

    public init(title: String, tone: StatusTone) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        StatusLabel(title: title, tone: tone)
            .font(.headline)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background(tone.color.opacity(0.15), in: .rect(cornerRadius: Radius.tile))
    }
}
