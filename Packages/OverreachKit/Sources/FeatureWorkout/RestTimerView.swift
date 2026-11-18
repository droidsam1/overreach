import DesignSystem
import SwiftUI
import WorkoutPresentation

// Views only: layout and styling. Times and texts come from `RestTimerModel` (ADR-0014).

/// The rest countdown, shown above the bottom of the session.
struct RestTimerView: View {
    let model: RestTimerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let state = model.state(at: context.date) {
                content(state)
                    .sensoryFeedback(.success, trigger: state.isFinished) { _, finished in finished }
            }
        }
    }

    private func content(_ state: RestTimerState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(state.title).font(.headline)
                    Text(state.exerciseName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.remaining)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .accessibilityLabel("Time remaining \(state.remaining)")
            }
            ProgressView(value: state.progress)
            HStack {
                Button("−15 s") { model.removeTime() }
                    .accessibilityLabel("Remove 15 seconds")
                Button("+15 s") { model.addTime() }
                    .accessibilityLabel("Add 15 seconds")
                Spacer()
                Button(state.dismissTitle) { model.skip() }
            }
            .buttonStyle(.bordered)
            Text(state.suggestion).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(Spacing.medium)
        .background(.bar)
    }
}
