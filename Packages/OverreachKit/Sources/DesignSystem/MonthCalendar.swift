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

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var markerSize: CGFloat = 6

    /// - Parameter ringFraction: 0…1, or `nil` for no ring.
    public init(
        number: String, ringFraction: Double?, showsStrength: Bool, showsRun: Bool,
        isToday: Bool, isFuture: Bool, isSelected: Bool
    ) {
        self.number = number
        self.ringFraction = ringFraction
        self.showsStrength = showsStrength
        self.showsRun = showsRun
        self.isToday = isToday
        self.isFuture = isFuture
        self.isSelected = isSelected
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
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                    .padding(4)
            }
            .frame(width: ringSize, height: ringSize)
            .overlay {
                if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1).padding(-3)
                }
            }
            HStack(spacing: 3) {
                Circle().fill(ActivityColor.strength).opacity(showsStrength ? 1 : 0)
                Circle().fill(ActivityColor.run).opacity(showsRun ? 1 : 0)
            }
            .frame(width: markerSize * 2 + 3, height: markerSize)
        }
        .padding(.vertical, Spacing.xSmall)
        .frame(maxWidth: .infinity)
        .opacity(isFuture ? 0.35 : 1)
        .contentShape(.rect)
    }
}

/// A legend entry: a small marker and what it means.
public struct CalendarLegendItem: View {
    public enum Marker {
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
