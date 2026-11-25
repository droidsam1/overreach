import DesignSystem
import SwiftUI
import TodayPresentation

struct TodayMovement: View {
    let model: TodayModel

    /// Steps and walks against the usual day: context for today's training, with its evidence.
    var body: some View {
        Card(radius: Radius.tile) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Label("Everyday movement", systemImage: "figure.walk")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.movementNotes, id: \.self) { note in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(note.text).font(.subheadline)
                        if let evidence = note.evidence {
                            Text(evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
