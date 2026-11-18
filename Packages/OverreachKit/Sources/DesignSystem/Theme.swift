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
