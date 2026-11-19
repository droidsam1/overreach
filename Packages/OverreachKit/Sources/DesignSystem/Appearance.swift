import SwiftUI

/// The app's light/dark appearance, chosen in Settings. Stored per device (`@AppStorage`): purely visual.
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    /// `@AppStorage` key shared by the picker (Settings) and the root view that applies it.
    public static let storageKey = "settings.appearance"

    public var id: String { rawValue }

    /// `nil` follows the iPhone's setting.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var title: LocalizedStringKey {
        switch self {
        case .system: "Same as the iPhone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
