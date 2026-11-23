import SwiftUI

/// A slowly moving tinted gradient for welcome-style screens. Still when Reduce Motion is on.
public struct AnimatedBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            Rectangle().fill(.background)
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                mesh(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func mesh(at time: TimeInterval) -> some View {
        let centerX = Float(0.5 + 0.15 * sin(time * 0.45))
        let centerY = Float(0.5 + 0.15 * cos(time * 0.35))
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [centerX, centerY], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .accentColor.opacity(0.35), .accentColor.opacity(0.12), .clear,
                .accentColor.opacity(0.08), .accentColor.opacity(0.25), .accentColor.opacity(0.05),
                .clear, .accentColor.opacity(0.1), .accentColor.opacity(0.3),
            ]
        )
    }
}

/// A feature or novelty: tinted symbol, title and a short detail.
public struct FeatureHighlightRow: View {
    private let symbol: String
    private let title: Text
    private let detail: Text?

    public init(symbol: String, title: Text, detail: Text? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline)
                if let detail {
                    detail.font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Page dots: the current page is wider and tinted.
public struct PageDots: View {
    private let count: Int
    private let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(count: Int, index: Int) {
        self.count = count
        self.index = index
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { page in
                Capsule()
                    .fill(page == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.4)))
                    .frame(width: page == index ? 22 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: index)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
    }
}

/// A large tappable choice: symbol, title and detail. Selected cards fill with the tint, grow a little and show a
/// check, with a springy animation; VoiceOver reads them as selectable buttons.
public struct ChoiceCard: View {
    private let symbol: String
    private let title: Text
    private let detail: Text?
    private let isSelected: Bool
    private let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(symbol: String, title: Text, detail: Text? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.medium) {
                Image(systemName: symbol)
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.12)))
                    )
                    .symbolEffect(.bounce, value: isSelected)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.headline).foregroundStyle(.primary)
                    if let detail {
                        detail.font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            )
            .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.4), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview("Visual Today · Light") {
    VisualTodayGallery().preferredColorScheme(.light)
}

#Preview("Visual Today · Dark") {
    VisualTodayGallery().preferredColorScheme(.dark)
}

#Preview("Visual Today · AX3 text, dark") {
    VisualTodayGallery()
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}

/// Every Visual Today component (ADR-0042) in one place, to check light, dark, large text, VoiceOver labels and
/// Reduce Motion together. Sample values only; each component also has its own previews.
struct VisualTodayGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                section("Readiness ring and badge") {
                    HStack(spacing: Spacing.medium) {
                        ForEach(StatusTone.allCases, id: \.self) { tone in
                            ReadinessRing(tone: tone, fraction: 0.8, size: 44, accessibilityLabel: "Readiness")
                        }
                    }
                    StatusBadge(title: "Amber · Train lighter", tone: .caution)
                }
                section("Signal tiles and trends") {
                    SignalTileRow {
                        SignalTile(
                            title: "HRV", value: "34", unit: "ms", status: "↓ Below usual", tone: .caution,
                            emphasized: true, accessibilityLabel: "HRV, 34 milliseconds, below your usual range",
                            action: {},
                            accessory: {
                                SignalTrendChart(values: [50, 52, 49, 41, 38, 36, 34], band: 46...56, tone: .caution)
                            }
                        )
                        SignalTile(
                            title: "Sleep", value: "7.2", unit: "h", status: "In range",
                            accessibilityLabel: "Sleep, 7.2 hours, in range", action: {},
                            accessory: {
                                SignalTrendChart(values: [7, 7.5, nil, 6.8, 7.2], band: 6.5...8, style: .bars)
                            }
                        )
                    }
                    SignalTrendChart(
                        values: [50, 52, 49, 41, 38, 36, 34], band: 46...56, tone: .caution, size: .full,
                        startLabel: "14 d", endLabel: "Today", summary: "HRV falling below your usual range"
                    )
                    RangeGauge(
                        value: 1.6, scale: 0...2, usual: 0.8...1.3, tone: .critical, accessibilityLabel: "Load 1.6"
                    )
                }
                section("Your week") {
                    WeekStrip(days: galleryDays)
                    ProgressBar(
                        segments: [
                            .init(fraction: 0.33, color: WeekDayKind.strengthColor),
                            .init(fraction: 0.17, color: WeekDayKind.runColor),
                        ],
                        accessibilityLabel: "This week", accessibilityValue: "3 of 6"
                    )
                }
                section("Check-in and links") {
                    AnswerScale(options: galleryAnswers, selectedID: "4") { _ in }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: 2)) {
                        Button {} label: { LinkTile(title: "Why", symbolName: "questionmark.circle", color: .orange) }
                        Button {} label: {
                            LinkTile(title: "Recovery", symbolName: "heart.text.square", color: .teal)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.medium)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(verbatim: title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

private let galleryDays: [WeekDay] = [
    .init(id: 0, initial: "M", kind: .strengthDone, accessibilityLabel: "Monday: strength done"),
    .init(id: 1, initial: "T", kind: .runDone, accessibilityLabel: "Tuesday: run done"),
    .init(id: 2, initial: "W", kind: .restLogged, accessibilityLabel: "Wednesday: rest logged"),
    .init(id: 3, initial: "T", kind: .today, accessibilityLabel: "Thursday: today"),
    .init(id: 4, initial: "F", kind: .plannedStrength, accessibilityLabel: "Friday: strength planned"),
    .init(id: 5, initial: "S", kind: .plannedRun, accessibilityLabel: "Saturday: run planned"),
    .init(id: 6, initial: "S", kind: .empty, accessibilityLabel: "Sunday: nothing planned"),
]

private let galleryAnswers = [
    AnswerOption(id: "1", symbolName: "cloud.bolt", label: "Awful"),
    AnswerOption(id: "2", symbolName: "cloud.rain", label: "Low"),
    AnswerOption(id: "3", symbolName: "minus.circle", label: "Okay"),
    AnswerOption(id: "4", symbolName: "sun.min", label: "Good"),
    AnswerOption(id: "5", symbolName: "sun.max", label: "Great"),
]

#endif
