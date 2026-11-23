import DesignSystem
import SwiftUI
import TodayPresentation

/// A profile question asked in context (ADR-0041, rule 5): one tap answers it, "Later" brings it back tomorrow.
struct ProfileQuestionPrompt: View {
    let card: ProfileQuestionCard
    let answer: (String) -> Void
    let later: () -> Void

    var body: some View {
        TodayPromptCard(title: Text(card.title), detail: Text(card.detail), dismiss: later) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(card.answers) { option in
                    Button(option.title) { answer(option.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button("Later", action: later)
                    .controlSize(.large)
            }
        }
    }
}
