import SwiftUI

/// A card showing one metric, e.g. "HRV 37 ms". Shows "–" when the value is missing.
public struct MetricTile: View {
    private let title: LocalizedStringKey
    private let value: Double?
    private let unit: LocalizedStringKey
    private let fractionDigits: Int
    private let caption: String?

    /// - Parameter caption: a short context line under the value, e.g. "7-day avg 42 ms".
    public init(
        title: LocalizedStringKey, value: Double?, unit: LocalizedStringKey, fractionDigits: Int = 0,
        caption: String? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.fractionDigits = fractionDigits
        self.caption = caption
    }

    private var formattedValue: String {
        value.map { $0.formatted(.number.precision(.fractionLength(fractionDigits))) } ?? "–"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(formattedValue)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                if value != nil {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Uses readable system text and a separate semantic symbol.
public struct StatusLabel: View {
    private let title: String
    private let tone: StatusTone

    public init(title: String, tone: StatusTone) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
        }
    }
}

/// A tinted badge for a semantic status, such as a readiness level.
public struct StatusBadge: View {
    private let title: String
    private let tone: StatusTone

    public init(title: String, tone: StatusTone) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        StatusLabel(title: title, tone: tone)
            .font(.headline)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background(tone.color.opacity(0.15), in: .rect(cornerRadius: Radius.card))
    }
}

/// Placeholder for screens that arrive in a later phase.
public struct ComingSoonView: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let phase: Int

    public init(title: LocalizedStringKey, systemImage: String, phase: Int) {
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
