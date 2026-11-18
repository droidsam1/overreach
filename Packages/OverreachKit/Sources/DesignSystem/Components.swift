import SwiftUI

/// A card showing one metric, e.g. "HRV 37 ms". Shows "–" when the value is missing.
public struct MetricTile: View {
    private let title: String
    private let value: Double?
    private let unit: String
    private let fractionDigits: Int

    public init(title: String, value: Double?, unit: String, fractionDigits: Int = 0) {
        self.title = title
        self.value = value
        self.unit = unit
        self.fractionDigits = fractionDigits
    }

    private var formattedValue: String {
        value.map { $0.formatted(.number.precision(.fractionLength(fractionDigits))) } ?? "–"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(formattedValue)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                if value != nil {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// A capsule with a status and its tone, e.g. a traffic light.
public struct StatusBadge: View {
    private let title: String
    private let tone: StatusTone

    public init(title: String, tone: StatusTone) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Label(title, systemImage: tone.symbolName)
            .font(.headline)
            .foregroundStyle(tone.color)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background(tone.color.opacity(0.15), in: .capsule)
    }
}

/// Placeholder for screens that arrive in a later phase.
public struct ComingSoonView: View {
    private let title: String
    private let systemImage: String
    private let phase: Int

    public init(title: String, systemImage: String, phase: Int) {
        self.title = title
        self.systemImage = systemImage
        self.phase = phase
    }

    public var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text("Coming in phase \(phase).")
            )
            .navigationTitle(title)
        }
    }
}

#Preview("Components") {
    VStack(spacing: Spacing.medium) {
        StatusBadge(title: "Amber", tone: .caution)
        HStack {
            MetricTile(title: "HRV", value: 37, unit: "ms")
            MetricTile(title: "Sleep", value: nil, unit: "h")
        }
    }
    .padding()
}
