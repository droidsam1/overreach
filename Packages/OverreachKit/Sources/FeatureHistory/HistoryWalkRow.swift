import DesignSystem
import HistoryPresentation
import SwiftUI

struct HistoryWalkRow: View {
    let walk: HistoryWalk
    let companion: HistoryWalkCompanion?
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Label(walk.title, systemImage: "figure.walk").font(.headline)
            Text(walk.detail).font(.subheadline).foregroundStyle(.secondary)
            Text(walk.sourceText).font(.caption).foregroundStyle(.secondary)
            if let companion {
                companionControl(companion)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(companion.question) \(walk.detail)")
            }
        }
    }

    @ViewBuilder
    private func companionControl(_ companion: HistoryWalkCompanion) -> some View {
        if companion.showsSuggestion {
            Text(companion.question)
            HStack {
                answers
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Menu {
                answers
            } label: {
                LabeledContent {
                    if let answer = companion.answer { Text(answer) }
                } label: {
                    Label(companion.question, systemImage: "dog")
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var answers: some View {
        Group {
            Button("Yes") { answer(true) }
            Button("No") { answer(false) }
        }
    }
}
