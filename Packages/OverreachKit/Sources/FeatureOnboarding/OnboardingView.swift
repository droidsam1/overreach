import DesignSystem
import Domain
import OnboardingPresentation
import SwiftUI

// Views only: layout, styling and static copy. Steps and rules come from `OnboardingPresentation` (ADR-0014).

/// Optional first-run setup: goal, about you, walking routine and how to start.
public struct OnboardingView: View {
    @Bindable private var model: OnboardingModel
    private let onFinish: (OnboardingDestination) -> Void

    public init(model: OnboardingModel, onFinish: @escaping (OnboardingDestination) -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
                switch model.step {
                case .goal: goalStep
                case .about: aboutStep
                case .walking: walkingStep
                case .start: startStep
                }
            }
            .navigationTitle(title)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var title: LocalizedStringKey {
        switch model.step {
        case .goal: "Welcome"
        case .about: "About you"
        case .walking: "Walking"
        case .start: "Get started"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if model.canGoBack {
                Button("Back") { model.back() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Skip setup") { Task { await model.skipSetup() } }
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.small) {
            Text(model.progressText).font(.caption).foregroundStyle(.secondary)
            if model.canSkipStep {
                HStack {
                    Button("Skip") { model.skipStep() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Continue") { model.next() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(Spacing.medium)
        .background(.bar)
    }

    private var goalStep: some View {
        Section {
            Picker("Goal", selection: $model.goalKind) {
                ForEach(model.goalOptions) { option in
                    Text(option.name).tag(TrainingGoal.Kind?.some(option.value))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("What are you training for?")
        } footer: {
            Text("Plan advice is judged against this goal. You can change it in Plan.")
        }
    }

    @ViewBuilder
    private var aboutStep: some View {
        Section {
            Picker("Sex", selection: $model.sex) {
                ForEach(model.sexOptions) { option in
                    Text(option.name).tag(BiologicalSex?.some(option.value))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Sex")
        } footer: {
            Text("Optional. It is only used as training context.")
        }
        if model.showsCycleTracking {
            Section {
                Picker("Cycle tracking", selection: $model.cycleTracking) {
                    ForEach(model.cycleOptions) { option in
                        Text(option.name).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Cycle tracking")
            } footer: {
                Text("""
                    Context for reading recovery, never a fixed rule or a diagnosis. It stays in your own data \
                    and backups.
                    """)
            }
        }
    }

    private var walkingStep: some View {
        Section {
            Toggle("I walk a dog", isOn: $model.hasDog)
            Picker("Usual walks per day", selection: $model.usualWalksPerDay) {
                Text("Not sure").tag(Int?.none)
                ForEach(model.walkOptions) { option in
                    Text(option.name).tag(Int?.some(option.value))
                }
            }
            if model.showsWalkDetails {
                Toggle("These walks can't be skipped", isOn: $model.walksAreFixed)
                Toggle("I can jog during them", isOn: $model.canRunDuringWalks)
            }
        } footer: {
            Text("Advice adapts to your walks and never removes the ones you can't skip.")
        }
    }

    private var startStep: some View {
        Section {
            Button("Import from Strong", systemImage: "square.and.arrow.down") { finish(.importHistory) }
            Button("Start with the exercise catalog", systemImage: "dumbbell") { finish(.train) }
        } header: {
            Text("How do you want to start?")
        } footer: {
            Text("Importing continues in Settings, where you choose your Strong CSV file.")
        }
    }

    private func finish(_ destination: OnboardingDestination) {
        Task {
            if await model.finish() { onFinish(destination) }
        }
    }
}
