import SwiftUI

/// Spacing scale. Use these instead of literal numbers.
public enum Spacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
}

public enum Radius {
    public static let card: CGFloat = 16
}

/// Semantic look of a status, independent of what the status means.
public enum StatusTone: Sendable {
    case positive
    case caution
    case critical
    case neutral

    public var color: Color {
        switch self {
        case .positive: .green
        case .caution: .orange
        case .critical: .red
        case .neutral: .secondary
        }
    }

    public var symbolName: String {
        switch self {
        case .positive: "checkmark.circle.fill"
        case .caution: "exclamationmark.circle.fill"
        case .critical: "xmark.octagon.fill"
        case .neutral: "questionmark.circle"
        }
    }
}

/// The brand accent uses different luminance in light and dark appearances.
public struct BrandButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                Color.accentColor
                    .overlay {
                        if configuration.isPressed {
                            (colorScheme == .dark ? Color.white : Color.black).opacity(0.1)
                        }
                    }
            }
            .clipShape(.rect(cornerRadius: Radius.card))
            .contentShape(.rect(cornerRadius: Radius.card))
            .opacity(isEnabled ? 1 : 0.5)
    }
}
