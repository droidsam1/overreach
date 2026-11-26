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
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
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
                    progressBar(state)
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.xSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                .haptic(.completed, trigger: state.isFinished) { _, finished in finished }
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
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
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
            let symbol = state.isFinished ? StatusTone.done.symbolName : "timer.circle"
            let color: Color = state.isFinished ? StatusTone.done.accent : .accentColor
            HStack(spacing: Spacing.small) {
                IconTile(symbolName: symbol, color: color)
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    Text(state.title).font(.headline)
                    countdown(state).font(.headline)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens rest timer details")
    }

    private func progressBar(_ state: RestTimerState) -> some View {
        let color: Color = state.isFinished ? StatusTone.done.accent : .accentColor
        return ProgressBar(
            segments: [.init(fraction: state.progress, color: color)], height: Spacing.xSmall,
            accessibilityLabel: state.title, accessibilityValue: state.remaining
        )
        .accessibilityHidden(true)
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
                Text(state.title).font(.subheadline)
                progressBar(state)
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
