import DesignSystem
import SwiftUI

struct MatchReviewCard: View {
    let title: LocalizedStringKey
    let symbol: String
    let count: Int

    var body: some View {
        Card {
            HStack(spacing: Spacing.small) {
                Label(title, systemImage: symbol).font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(count, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
