import SwiftUI

/// A recovery signal as one button: title, value and unit, a compact trend and a short status line.
/// `emphasized` draws the tone's accent border for the signal that drives today's verdict. Display values only.
public struct SignalTile<Accessory: View>: View {
    private let title: String
    private let value: String
    private let unit: String?
    private let status: String
    private let tone: StatusTone
    private let emphasized: Bool
    private let accessibilityText: String
    private let action: () -> Void
    private let accessory: Accessory

    /// `accessory` is normally a compact `TrendChart`; pass `EmptyView` when there is no trend.
    /// `accessibilityLabel` reads the whole tile ("HRV, 34 milliseconds, below your usual range").
    public init(
        title: String, value: String, unit: String? = nil, status: String, tone: StatusTone = .neutral,
        emphasized: Bool = false, accessibilityLabel: String, action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.status = status
        self.tone = tone
        self.emphasized = emphasized
        self.accessibilityText = accessibilityLabel
        self.action = action
        self.accessory = accessory()
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(verbatim: title).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: value).font(.title3.weight(.heavy))
                    if let unit {
                        Text(verbatim: unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
                accessory.accessibilityHidden(true)
                Text(verbatim: status)
                    .font(.caption)
                    .foregroundStyle(emphasized ? tone.accent : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.small + Spacing.xSmall)
            .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.card))
            .overlay {
                if emphasized {
                    RoundedRectangle(cornerRadius: Radius.card).stroke(tone.accent, lineWidth: 1.5)
                }
            }
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}

extension SignalTile where Accessory == EmptyView {
    public init(
        title: String, value: String, unit: String? = nil, status: String, tone: StatusTone = .neutral,
        emphasized: Bool = false, accessibilityLabel: String, action: @escaping () -> Void
    ) {
        self.init(
            title: title, value: value, unit: unit, status: status, tone: tone, emphasized: emphasized,
            accessibilityLabel: accessibilityLabel, action: action
        ) { EmptyView() }
    }
}

/// Lays tiles out side by side, and stacks them vertically when they no longer fit (accessibility sizes).
public struct SignalTileRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.small) { content }
            VStack(spacing: Spacing.small) { content }
        }
    }
}

#Preview("Tiles") {
    SignalTileRow {
        SignalTile(
            title: "HRV", value: "34", unit: "ms", status: "↓ Below usual", tone: .caution, emphasized: true,
            accessibilityLabel: "HRV, 34 milliseconds, below your usual range", action: {}
        ) {
            TrendChart(values: [50, 52, 49, 41, 38, 36, 34], band: 46...56, tone: .caution)
        }
        SignalTile(
            title: "Sleep", value: "7.2", unit: "h", status: "In range",
            accessibilityLabel: "Sleep, 7.2 hours, in range", action: {}
        ) {
            TrendChart(values: [7, 7.5, nil, 6.8, 7.2], band: 6.5...8, style: .bars)
        }
        SignalTile(
            title: "Resting HR", value: "—", status: "No data", accessibilityLabel: "Resting heart rate, no data",
            action: {}
        )
    }
    .padding()
}

#Preview("Accessibility size, dark") {
    SignalTileRow {
        SignalTile(title: "HRV", value: "34", unit: "ms", status: "In range", accessibilityLabel: "HRV", action: {})
        SignalTile(title: "Sleep", value: "7", unit: "h", status: "In range", accessibilityLabel: "Sleep", action: {})
    }
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
