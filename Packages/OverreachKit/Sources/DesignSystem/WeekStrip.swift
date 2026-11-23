import SwiftUI

/// What one day of the week strip shows. A display kind, not a domain type: the caller maps its own days to it.
public enum WeekDayKind: Sendable, CaseIterable {
    case strengthDone
    case runDone
    case restLogged
    case plannedStrength
    case plannedRun
    /// Today with nothing logged yet.
    case today
    /// Nothing done or planned.
    case empty

    /// Violet, the colour of strength.
    public static let strengthColor = Color(light: 0x6D28D9, dark: 0xA78BFA)
    /// Blue, the colour of runs.
    public static let runColor = Color(light: 0x1D5FC4, dark: 0x5AA9FF)

    var color: Color {
        switch self {
        case .strengthDone, .plannedStrength: Self.strengthColor
        case .runDone, .plannedRun: Self.runColor
        case .restLogged: StatusTone.positive.accent
        case .today: Color.primary
        case .empty: Color.secondary
        }
    }

    /// Every colour comes with a symbol; empty days have none.
    var symbolName: String? {
        switch self {
        case .strengthDone, .plannedStrength: "dumbbell.fill"
        case .runDone, .plannedRun: "figure.run"
        case .restLogged: "moon.fill"
        case .today: "circle.fill"
        case .empty: nil
        }
    }

    var isFilled: Bool { self == .strengthDone || self == .runDone }
}

/// One cell of the strip. `accessibilityLabel` is the whole sentence, such as "Tuesday: run done".
public struct WeekDay: Identifiable, Sendable {
    public let id: Int
    public let initial: String
    public let kind: WeekDayKind
    public let accessibilityLabel: String

    public init(id: Int, initial: String, kind: WeekDayKind, accessibilityLabel: String) {
        self.id = id
        self.initial = initial
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Seven day cells: weekday initial over a circle that shows what was done or is planned. Display values only.
public struct WeekStrip: View {
    private let days: [WeekDay]

    public init(days: [WeekDay]) {
        self.days = days
    }

    public var body: some View {
        HStack(spacing: Spacing.xSmall) {
            ForEach(days) { day in
                DayCell(day: day)
            }
        }
    }
}

private struct DayCell: View {
    let day: WeekDay
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 34

    var body: some View {
        let kind = day.kind
        VStack(spacing: Spacing.xSmall) {
            Text(verbatim: day.initial)
                .font(.caption.weight(kind == .today ? .heavy : .regular))
                .foregroundStyle(kind == .today ? Color.primary : Color.secondary)
            // Shrinks to the cell's width so seven days still fit at accessibility text sizes.
            circle
                .frame(maxWidth: min(diameter, 60), maxHeight: min(diameter, 60))
                .aspectRatio(1, contentMode: .fit)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
    }

    @ViewBuilder private var circle: some View {
        let kind = day.kind
        ZStack {
            if kind.isFilled {
                Circle().fill(kind.color)
            } else if kind == .empty {
                Circle().strokeBorder(kind.color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            } else if kind == .today {
                Circle().strokeBorder(kind.color, lineWidth: 3)
            } else {
                Circle().strokeBorder(kind.color, lineWidth: 2)
            }
            if let symbol = kind.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: kind == .today ? 6 : 14, weight: .semibold))
                    .foregroundStyle(kind.isFilled ? StatusTone.positive.onAccent : kind.color)
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview("Week, light") {
    WeekStrip(days: previewDays).padding().preferredColorScheme(.light)
}

#Preview("Week, dark") {
    WeekStrip(days: previewDays).padding().preferredColorScheme(.dark)
}

#Preview("Accessibility size") {
    WeekStrip(days: previewDays).padding().environment(\.dynamicTypeSize, .accessibility3)
}

private let previewDays: [WeekDay] = [
    .init(id: 0, initial: "M", kind: .strengthDone, accessibilityLabel: "Monday: strength done"),
    .init(id: 1, initial: "T", kind: .runDone, accessibilityLabel: "Tuesday: run done"),
    .init(id: 2, initial: "W", kind: .restLogged, accessibilityLabel: "Wednesday: rest logged"),
    .init(id: 3, initial: "T", kind: .today, accessibilityLabel: "Thursday: today"),
    .init(id: 4, initial: "F", kind: .plannedStrength, accessibilityLabel: "Friday: strength planned"),
    .init(id: 5, initial: "S", kind: .plannedRun, accessibilityLabel: "Saturday: run planned"),
    .init(id: 6, initial: "S", kind: .empty, accessibilityLabel: "Sunday: nothing planned"),
]
