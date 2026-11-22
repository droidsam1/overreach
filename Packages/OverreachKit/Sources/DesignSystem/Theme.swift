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
public enum StatusTone: Sendable, CaseIterable {
    case positive
    case caution
    case critical
    case neutral
    /// Training done today (violet).
    case done

    public var color: Color {
        switch self {
        case .positive: .green
        case .caution: .orange
        case .critical: .red
        case .neutral: .secondary
        case .done: .purple
        }
    }

    public var symbolName: String {
        switch self {
        case .positive: "checkmark.circle.fill"
        case .caution: "exclamationmark.circle.fill"
        case .critical: "xmark.octagon.fill"
        case .neutral: "questionmark.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    /// The character shown in the centre of a `ReadinessRing`.
    public var ringGlyph: String {
        switch self {
        case .positive, .done: "✓"
        case .caution: "–"
        case .critical: "✕"
        case .neutral: "?"
        }
    }

    /// Card tint behind the hero.
    public var surface: Color { Color(light: surfaceHex.light, dark: surfaceHex.dark) }
    /// Card outline. Clear for the neutral tone.
    public var border: Color {
        guard let hex = borderHex else { return .clear }
        return Color(light: hex.light, dark: hex.dark)
    }
    /// Ring, button and badge fill.
    public var accent: Color { Color(light: accentHex.light, dark: accentHex.dark) }
    /// Text and symbols drawn on `accent`.
    public var onAccent: Color { Color(light: onAccentHex.light, dark: onAccentHex.dark) }

    // Hex pairs (light, dark). Dark values come from the mock-ups, light ones keep the same roles with
    // at least 4.5:1 for `onAccent` on `accent` and for primary text on `surface` (docs/design/today-visual.md).
    var accentHex: (light: UInt32, dark: UInt32) {
        switch self {
        case .positive: (0x15803D, 0x4ADE80)
        case .caution: (0xB45309, 0xF5A524)
        case .critical: (0xB91C1C, 0xF87171)
        case .done: (0x6D28D9, 0xA78BFA)
        case .neutral: (0x4B5563, 0x9CA3AF)
        }
    }

    var onAccentHex: (light: UInt32, dark: UInt32) {
        (0xFFFFFF, 0x0E1013)
    }

    var surfaceHex: (light: UInt32, dark: UInt32) {
        switch self {
        case .positive: (0xE8F7EE, 0x13261B)
        case .caution: (0xFFF3DC, 0x2A1F0C)
        case .critical: (0xFDEAEA, 0x2A1212)
        case .done: (0xEEE9FD, 0x1E1836)
        case .neutral: (0xF1F2F4, 0x1A1D22)
        }
    }

    var borderHex: (light: UInt32, dark: UInt32)? {
        switch self {
        case .positive: (0xA7DDBB, 0x1F4A31)
        case .caution: (0xF0CF8E, 0x5A4116)
        case .critical: (0xF3B4B4, 0x5A1E1E)
        case .done: (0xCFC2F6, 0x3A2E66)
        case .neutral: nil
        }
    }
}

extension Color {
    /// A colour that follows the appearance, from 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #endif
    }
}

#if canImport(UIKit)
import UIKit

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
import AppKit

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

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
