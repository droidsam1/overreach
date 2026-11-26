import SwiftUI

/// Colours of the activity markers, shared by calendar cells and their legend. Each reads well in light and dark.
public enum ActivityColor {
    public static let strength = Color.accentColor
    public static let run = Color.green
    public static let steps = Color.blue
}

/// One day of a month grid: the day number inside a progress ring, with a strength and a run marker below.
/// Takes display values only; what they mean is decided by the caller's model.
public struct CalendarDayView: View {
    private let number: String
    private let ringFraction: Double?
    private let showsStrength: Bool
    private let showsRun: Bool
    private let isToday: Bool
    private let isFuture: Bool
    private let isSelected: Bool
    private let isRest: Bool

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 34
    @ScaledMetric(relativeTo: .caption2) private var markerSize: CGFloat = 7

    /// - Parameter ringFraction: 0…1, or `nil` for no ring.
    public init(
        number: String, ringFraction: Double?, showsStrength: Bool, showsRun: Bool,
        isToday: Bool, isFuture: Bool, isSelected: Bool, isRest: Bool = false
    ) {
        self.number = number
        self.ringFraction = ringFraction
        self.showsStrength = showsStrength
        self.showsRun = showsRun
        self.isToday = isToday
        self.isFuture = isFuture
        self.isSelected = isSelected
        self.isRest = isRest
    }

    public var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.accentColor.opacity(0.18))
                }
                if let ringFraction {
                    Circle()
                        .stroke(ActivityColor.steps.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: ringFraction)
                        .stroke(ActivityColor.steps, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(number)
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .foregroundStyle(isFuture ? .secondary : .primary)
                    .padding(4)
            }
            .frame(width: min(ringSize, 38), height: min(ringSize, 38))
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color.primary.opacity(0.7), lineWidth: 1).padding(-2)
                } else if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1).padding(-2)
                }
            }
            let marker = min(markerSize, 10)
            HStack(spacing: Spacing.xSmall) {
                RoundedRectangle(cornerRadius: 1).fill(ActivityColor.strength)
                    .frame(width: marker, height: marker)
                    .opacity(showsStrength ? 1 : 0)
                Circle().fill(ActivityColor.run)
                    .frame(width: marker, height: marker)
                    .opacity(showsRun ? 1 : 0)
                if isRest {
                    Image(systemName: "moon.fill").font(.system(size: marker)).foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xSmall)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
    }
}

/// A legend entry: a small marker and what it means.
public struct CalendarLegendItem: View {
    public enum Marker {
        case square(Color)
        case dot(Color)
        case ring(Color)
    }

    private let marker: Marker
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey, marker: Marker) {
        self.title = title
        self.marker = marker
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            switch marker {
            case .square(let color):
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
            case .dot(let color):
                Circle().fill(color).frame(width: 8, height: 8)
            case .ring(let color):
                Circle().trim(from: 0, to: 0.7)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 11, height: 11)
            }
        }
        .labelStyle(LegendLabelStyle())
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xSmall) {
            configuration.icon
            configuration.title
        }
    }
}

/// A number with a caption under it, e.g. "12" over "Sessions".
public struct CompactStat: View {
    private let value: String
    private let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
