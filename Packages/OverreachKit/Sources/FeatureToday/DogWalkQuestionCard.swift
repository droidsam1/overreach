import DesignSystem
import SwiftUI
import TodayPresentation

/// "With Nanoq?" with one tap to answer. Never blocks anything.
struct DogWalkQuestionCard: View {
    let question: DogWalkQuestion
    let dismiss: () -> Void
    let answer: (Bool) -> Void

    var body: some View {
        TodayPromptCard(title: Text(question.text), detail: Text(question.detail), dismiss: dismiss) {
            HStack(spacing: Spacing.small) {
                Button("Yes") { answer(true) }
                Button("No") { answer(false) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .accessibilityLabel(question.accessibilityLabel)
    }
}
