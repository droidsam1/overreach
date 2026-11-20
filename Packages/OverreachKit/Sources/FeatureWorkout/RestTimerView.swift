import DesignSystem
import SwiftUI
import WorkoutPresentation

/// The compact rest countdown stays above the session. Adjustments open on demand.
struct RestTimerView: View {
    let model: RestTimerModel
    @State private var isShowingDetails = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let state = model.state(at: context.date) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.small) {
                        countdownButton(state)
                        Spacer(minLength: 0)
                        skipButton(state)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        countdownButton(state)
                        skipButton(state)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.xSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                .sensoryFeedback(.success, trigger: state.isFinished) { _, finished in finished }
            }
        }
        .sheet(isPresented: $isShowingDetails) {
            NavigationStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let state = model.state(at: context.date) {
                        details(state)
                    }
                }
                .navigationTitle("Rest timer")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingDetails = false }
                    }
                }
            }
        }
    }

    private func countdownButton(_ state: RestTimerState) -> some View {
        Button {
            isShowingDetails = true
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) {
                    Text(state.title)
                    countdown(state)
                }
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(state.title)
                    countdown(state)
                }
            }
            .font(.headline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens rest timer details")
    }

    private func countdown(_ state: RestTimerState) -> some View {
        Text(state.remaining)
            .monospacedDigit()
            .accessibilityLabel("Time remaining \(state.remaining)")
    }

    private func skipButton(_ state: RestTimerState) -> some View {
        Button {
            model.skip()
        } label: {
            Group {
                if state.isFinished {
                    Text(state.dismissTitle)
                } else {
                    Text("Skip rest")
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private func details(_ state: RestTimerState) -> some View {
        List {
            Section {
                Text(state.exerciseName)
                    .font(.headline)
                countdown(state)
                    .font(.title.weight(.semibold))
                ProgressView(value: state.progress) {
                    Text(state.title)
                }
                Text(state.suggestion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("−15 s") { model.removeTime() }
                    .accessibilityLabel("Remove 15 seconds")
                Button("+15 s") { model.addTime() }
                    .accessibilityLabel("Add 15 seconds")
                skipButton(state)
            }
        }
    }
}
