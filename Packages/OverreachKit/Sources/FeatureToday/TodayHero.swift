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
            .background(tone.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: Radius.tile))
            .contentShape(.rect(cornerRadius: Radius.tile))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// The hero card of Today: ring, badge, verdict and one reason, the signal tiles and the primary action
/// (`docs/design/today-visual.md`, ADR-0042). `action` is the button (or the deload proposal) of the next action.
struct TodayHero<Action: View>: View {
    let model: TodayModel
    let openWhy: () -> Void
    @ViewBuilder let action: Action

    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(HeroMetrics.celebratedDayKey) private var celebratedDay = ""
    @State private var celebrates = false

    private var done: TodayDone? { model.doneToday }

    /// Violet once training is done, green for a rest day, otherwise the readiness tone.
    private var tone: StatusTone {
        guard done != nil else { return model.readinessLevel.tone }
        return model.nextAction == .restLogged ? .positive : .done
    }

    var body: some View {
        Card(tone: tone) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                summary
                if let done {
                    TodayDoneSummary(done: done, tone: tone)
                } else {
                    signals
                    action
                }
            }
        }
        .haptic(.completed, trigger: celebrates) { _, new in new }
        .onAppear(perform: celebrateFirstTime)
    }

    /// The first time the done state appears on a day: the ring fills (it always does, unless Reduce Motion is on)
    /// and a success haptic plays. Stored per device in `UserDefaults`, so it is not part of backups.
    private func celebrateFirstTime() {
        guard done != nil else { return }
        let today = Date.now.formatted(.iso8601.year().month().day())
        guard celebratedDay != today else { return }
        celebratedDay = today
        celebrates = true
    }

    /// Ring beside the verdict; at accessibility text sizes the ring sits above it so the verdict keeps the width.
    private var summaryLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.medium))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.medium))
    }

    private var summary: some View {
        summaryLayout {
            ReadinessRing(tone: tone, accessibilityLabel: done?.title ?? model.readinessTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.small) {
                if let done {
                    Text(verbatim: done.title)
                        .font(.title2.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                    if model.nextAction == .trainedToday {
                        Text(model.heroTitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    StatusBadge(title: model.readinessTitle, tone: tone).accessibilitySortPriority(1)
                    Text(model.heroTitle)
                        .font(.title2.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilitySortPriority(3)
                    Text(model.heroReason).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilitySortPriority(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        Card(tone: .neutral) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                HStack(alignment: .top, spacing: Spacing.medium) {
                    Circle().frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        Text(verbatim: String(repeating: "•", count: 6))
                        Text(verbatim: String(repeating: "•", count: 20)).font(.title2.weight(.heavy))
                        Text(verbatim: String(repeating: "•", count: 48)).font(.subheadline)
                    }
                }
                RoundedRectangle(cornerRadius: Radius.tile).frame(height: 96)
                RoundedRectangle(cornerRadius: Radius.tile).frame(height: 48)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading Today…"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

enum HeroMetrics {
    /// `UserDefaults` key of the last day the done state was celebrated (per device, not in backups).
    static let celebratedDayKey = "today.donecelebrated.day"
}
