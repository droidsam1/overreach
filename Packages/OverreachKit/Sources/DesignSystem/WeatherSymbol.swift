import SwiftUI

/// The three palette layers of a weather symbol, in SF Symbols order: the cloud (or the only shape), then the sun,
/// moon or bolt, then drops.
public struct WeatherPalette: Sendable {
    public let primary: Color
    public let secondary: Color
    public let tertiary: Color

    init(_ primary: Color, _ secondary: Color, _ tertiary: Color) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
    }
}

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

    public var layers: WeatherPalette {
        switch self {
        case .clear: WeatherPalette(.yellow, .yellow, .yellow)
        case .clearNight: WeatherPalette(.indigo, .yellow, .yellow)
        case .partlyCloudy: WeatherPalette(.gray, .yellow, .yellow)
        case .partlyCloudyNight: WeatherPalette(.gray, .indigo, .indigo)
        case .cloudy: WeatherPalette(.gray, .gray, .gray)
        case .rain: WeatherPalette(.gray, .blue, .blue)
        case .thunderstorm: WeatherPalette(.gray, .yellow, .blue)
        case .snow: WeatherPalette(.gray, .cyan, .cyan)
        case .fog: WeatherPalette(.gray, .secondary, .secondary)
        case .muted: WeatherPalette(.secondary, .secondary, .secondary)
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
