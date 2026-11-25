import DesignSystem
import Foundation
import SwiftUI

/// The activity date and key metrics, ahead of sources and supporting details.
struct HistorySummaryCard<Totals: View>: View {
    let date: Date
    private let totals: Totals

    init(date: Date, @ViewBuilder totals: () -> Totals) {
        self.date = date
        self.totals = totals()
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(date, format: .dateTime.weekday().day().month().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AdaptiveStack(spacing: Spacing.small) { totals }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct HistorySummaryTile: View {
    let label: LocalizedStringKey
    let value: Text

    var body: some View {
        Card(
            surface: AnyShapeStyle(Color.secondary.opacity(0.12)),
            radius: Radius.tile, padding: Spacing.small
        ) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                value.font(.title3.weight(.heavy)).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("History summary") {
    HistorySummaryPreview().preferredColorScheme(.light)
}

#Preview("History summary, dark and accessibility") {
    HistorySummaryPreview()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}

private struct HistorySummaryPreview: View {
    var body: some View {
        List {
            HistorySummaryCard(date: .now) {
                HistorySummaryTile(label: "Distance", value: Text(verbatim: "12.3 km"))
                HistorySummaryTile(label: "Duration", value: Text(verbatim: "1:04:28"))
                HistorySummaryTile(label: "Pace", value: Text(verbatim: "5:14 /km"))
            }
            MatchReviewCard(title: "Review run matches", symbol: "figure.run", count: 2)
        }
    }
}
