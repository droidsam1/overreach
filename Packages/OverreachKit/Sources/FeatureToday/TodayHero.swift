import DesignSystem
import Domain
import SwiftUI
import TodayPresentation

extension ReadinessLevel {
    /// How each readiness level looks on Today.
    var tone: StatusTone {
        switch self {
        case .green: .positive
        case .amber: .caution
        case .red: .critical
        case .unknown: .neutral
        }
    }
}

/// The primary button of the hero: the tone's accent with the text drawn on it (contrast pairs of ADR-0042).
struct ToneButtonStyle: ButtonStyle {
    let tone: StatusTone
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tone.onAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(tone.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: Radius.card))
            .contentShape(.rect(cornerRadius: Radius.card))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// The hero card of Today: ring, badge, verdict and one reason, the signal tiles and the primary action
/// (`docs/design/today-visual.md`, ADR-0042). `action` is the button (or the deload proposal) of the next action.
struct TodayHero<Action: View>: View {
    let model: TodayModel
    let openWhy: () -> Void
    @ViewBuilder let action: Action

    private var tone: StatusTone { model.readinessLevel.tone }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            summary
            signals
            action
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.surface, in: .rect(cornerRadius: HeroMetrics.radius))
        .overlay { RoundedRectangle(cornerRadius: HeroMetrics.radius).stroke(tone.border, lineWidth: 1) }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            ReadinessRing(tone: tone, accessibilityLabel: model.readinessTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.small) {
                StatusBadge(title: model.readinessTitle, tone: tone).accessibilitySortPriority(1)
                Text(model.heroTitle)
                    .font(.title2.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(3)
                Text(model.heroReason).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilitySortPriority(2)
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private var signals: some View {
        let signals = model.signals
        if !signals.isEmpty {
            SignalTileRow {
                ForEach(signals) { signal in
                    SignalTile(
                        title: signal.title, value: signal.value, unit: signal.unit.isEmpty ? nil : signal.unit,
                        status: signal.status, tone: signal.tone.tone, emphasized: signal.isLeading,
                        accessibilityLabel: [signal.title, "\(signal.value) \(signal.unit)", signal.status]
                            .joined(separator: ", "),
                        action: openWhy
                    ) {
                        SignalTrendChart(values: signal.trend, band: signal.band, tone: signal.tone.tone)
                    }
                }
            }
        }
    }
}

/// A card of the same size while Today loads, so the screen does not jump when the verdict arrives.
struct TodayHeroPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .top, spacing: Spacing.medium) {
                Circle().frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(verbatim: String(repeating: "•", count: 6))
                    Text(verbatim: String(repeating: "•", count: 20)).font(.title2.weight(.heavy))
                    Text(verbatim: String(repeating: "•", count: 48)).font(.subheadline)
                }
            }
            RoundedRectangle(cornerRadius: Radius.card).frame(height: 96)
            RoundedRectangle(cornerRadius: Radius.card).frame(height: 48)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatusTone.neutral.surface, in: .rect(cornerRadius: HeroMetrics.radius))
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading Today…"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

enum HeroMetrics {
    /// Corner radius of the hero card (spec: 24).
    static let radius: CGFloat = 24
}
