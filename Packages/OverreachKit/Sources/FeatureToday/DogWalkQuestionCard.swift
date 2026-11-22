import DesignSystem
import SwiftUI
import TodayPresentation

/// "With Nanoq?" with one tap to answer. Never blocks anything.
struct DogWalkQuestionCard: View {
    let question: DogWalkQuestion
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label(question.text, systemImage: "dog")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(question.detail).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: Spacing.small) {
                Button("Yes") { answer(true) }
                Button("No") { answer(false) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question.accessibilityLabel)
    }
}
