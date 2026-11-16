import Domain
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

public extension ReadinessLevel {
    /// Semantic colour of the readiness traffic light.
    var color: Color {
        switch self {
        case .green: .green
        case .amber: .orange
        case .red: .red
        case .unknown: .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .green: "checkmark.circle.fill"
        case .amber: "exclamationmark.circle.fill"
        case .red: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }
}
