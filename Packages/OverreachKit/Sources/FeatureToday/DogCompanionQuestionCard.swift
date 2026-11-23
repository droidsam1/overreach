import DesignSystem
import SwiftUI

/// "With Nanoq?" with one tap to answer. Never blocks anything.
struct DogCompanionQuestionCard: View {
    let title: String
    let detail: String
    let dismiss: () -> Void
    let answer: (Bool) -> Void

    var body: some View {
        TodayPromptCard(title: Text(title), detail: Text(detail), dismiss: dismiss) {
            HStack(spacing: Spacing.small) {
                Button("Yes") { answer(true) }
                Button("No") { answer(false) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .accessibilityLabel("\(title) \(detail)")
    }
}
