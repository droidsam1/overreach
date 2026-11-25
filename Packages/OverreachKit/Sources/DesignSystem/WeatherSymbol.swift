import SwiftUI

/// Colour roles of a weather symbol, independent of where the weather comes from.
public enum WeatherTone: Sendable, CaseIterable {
    case clear
    case clearNight
    case partlyCloudy
    case partlyCloudyNight
    case cloudy
    case rain
    case thunderstorm
    case snow
    case fog
    /// Not connected or no data: grey.
    case muted

    /// Palette layers in SF Symbols order: the cloud (or the only shape), then the sun, moon or bolt, then drops.
    public var layers: (primary: Color, secondary: Color, tertiary: Color) {
        switch self {
        case .clear: (.yellow, .yellow, .yellow)
        case .clearNight: (.indigo, .yellow, .yellow)
        case .partlyCloudy: (.gray, .yellow, .yellow)
        case .partlyCloudyNight: (.gray, .indigo, .indigo)
        case .cloudy: (.gray, .gray, .gray)
        case .rain: (.gray, .blue, .blue)
        case .thunderstorm: (.gray, .yellow, .blue)
        case .snow: (.gray, .cyan, .cyan)
        case .fog: (.gray, .secondary, .secondary)
        case .muted: (.secondary, .secondary, .secondary)
        }
    }
}

/// An SF Symbol drawn with the palette of a `WeatherTone`. Decorative: put the accessibility label on the parent.
public struct WeatherSymbol: View {
    private let systemName: String
    private let tone: WeatherTone

    public init(systemName: String, tone: WeatherTone) {
        self.systemName = systemName
        self.tone = tone
    }

    public var body: some View {
        let layers = tone.layers
        Image(systemName: systemName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(layers.primary, layers.secondary, layers.tertiary)
            .accessibilityHidden(true)
    }
}
