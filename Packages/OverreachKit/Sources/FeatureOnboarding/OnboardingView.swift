import DesignSystem
import Domain
import OnboardingPresentation
import SwiftUI

// Views only: layout, styling and static copy. Steps and rules come from `OnboardingPresentation` (ADR-0014).

/// Optional first-run setup: an animated tour of the app, then goal, about you, walking routine, devices and how to
/// start. Connecting Apple Health or Garmin from the devices step is wired by the App (other features' flows).
public struct OnboardingView: View {
    @Bindable private var model: OnboardingModel
    private let isGarminConnected: Bool
    private let onConnectHealth: () -> Void
    private let onConnectGarmin: () -> Void
    private let onFinish: (OnboardingDestination) -> Void
    @State private var askedForHealth = false

    public init(
        model: OnboardingModel,
        isGarminConnected: Bool = false,
        onConnectHealth: @escaping () -> Void = {},
        onConnectGarmin: @escaping () -> Void = {},
        onFinish: @escaping (OnboardingDestination) -> Void
    ) {
        self.model = model
        self.isGarminConnected = isGarminConnected
        self.onConnectHealth = onConnectHealth
        self.onConnectGarmin = onConnectGarmin
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            AnimatedBackdrop()
            if let page = model.tourPage {
                TourPageView(
                    content: TourContent.for(page), index: model.tourIndex, count: model.tourCount,
                    isLast: model.isLastTourPage, canGoBack: model.canGoBackInTour,
                    onNext: { model.nextTourPage() }, onBack: { model.previousTourPage() },
                    onSkipTour: { model.skipTour() }, onSkipSetup: { Task { await model.skipSetup() } }
                )
                .id(page)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                setup
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: model.tourPage)
    }

    private var setup: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
                switch model.step {
                case .goal: goalStep
                case .about: aboutStep
                case .walking: walkingStep
                case .devices: devicesStep
                case .start: startStep
                }
            }
            .scrollContentBackground(.hidden)
            .background(AnimatedBackdrop())
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
        case .devices: "Your devices"
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
                    Button("Continue") {
                        if model.continueTapped(isGarminConnected: isGarminConnected) { onConnectGarmin() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(Spacing.medium)
        .background(.bar)
    }

    private var goalStep: some View {
        Section {
            ForEach(model.goalOptions) { option in
                ChoiceCard(
                    symbol: Self.symbol(for: option.value), title: Text(option.name),
                    isSelected: model.goalKind == option.value
                ) {
                    model.goalKind = option.value
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
            }
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

    @ViewBuilder
    private var devicesStep: some View {
        Section {
            ForEach(model.wearableOptions, id: \.self) { wearable in
                card(wearable)
            }
            ChoiceCard(
                symbol: "iphone", title: Text("Only my iPhone"),
                detail: Text("Steps and walks; sleep if you track it in Health."),
                isSelected: model.usesOnlyPhone
            ) {
                model.chooseOnlyPhone()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
        } header: {
            Text("Which devices do you use?")
        } footer: {
            Text("Pick all that apply. The app only shows what your devices measure.")
        }
        Section {
            Button {
                askedForHealth = true
                onConnectHealth()
            } label: {
                Label(
                    askedForHealth ? "Apple Health requested" : "Allow Apple Health",
                    systemImage: askedForHealth ? "checkmark.circle.fill" : "heart.text.square.fill"
                )
            }
            .disabled(askedForHealth)
            if model.offersGarminSetup {
                if isGarminConnected {
                    Label("Garmin connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: onConnectGarmin) {
                        Label("Connect Garmin now", systemImage: "applewatch.radiowaves.left.and.right")
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        } header: {
            Text("Connect")
        } footer: {
            if model.offersGarminSetup && !isGarminConnected {
                Text("Three steps, about a minute. Or later from Today or Settings → Garmin.")
            } else {
                Text("Sleep, HRV, resting heart rate and steps come from Apple Health. You can change this in Settings.")
            }
        }
        .animation(.spring(duration: 0.4), value: model.offersGarminSetup)
        .animation(.spring(duration: 0.4), value: isGarminConnected)
    }

    private func card(_ wearable: Wearable) -> some View {
        Group {
            switch wearable {
            case .appleWatch:
                ChoiceCard(
                    symbol: "applewatch", title: Text("Apple Watch"),
                    detail: Text("HRV, resting heart rate, sleep and workouts through Apple Health."),
                    isSelected: model.isSelected(wearable)
                ) { model.toggle(wearable) }
            case .garmin:
                ChoiceCard(
                    symbol: "applewatch.radiowaves.left.and.right", title: Text("Garmin"),
                    detail: Text("Nightly HRV, sleep score, Body Battery and runs, with your own key."),
                    isSelected: model.isSelected(wearable)
                ) { model.toggle(wearable) }
            case .otherWatch:
                ChoiceCard(
                    symbol: "watch.analog", title: Text("Another watch or ring"),
                    detail: Text("Whatever it writes to Apple Health."),
                    isSelected: model.isSelected(wearable)
                ) { model.toggle(wearable) }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
    }

    private static func symbol(for goal: TrainingGoal.Kind) -> String {
        switch goal {
        case .strength: "figure.strengthtraining.traditional"
        case .hypertrophy: "figure.arms.open"
        case .general: "dumbbell.fill"
        case .hybrid: "figure.run"
        }
    }

    private var startStep: some View {
        Section {
            Button("Restore from a backup", systemImage: "arrow.counterclockwise.icloud") { finish(.restoreBackup) }
            Button("Import from Strong", systemImage: "square.and.arrow.down") { finish(.importHistory) }
            Button("Start with the exercise catalog", systemImage: "dumbbell") { finish(.train) }
        } header: {
            Text("How do you want to start?")
        } footer: {
            Text(
                """
                Restoring and importing continue in Settings: choose the iCloud Drive folder with your Overreach \
                backup, or your Strong CSV file.
                """
            )
        }
    }

    private func finish(_ destination: OnboardingDestination) {
        Task {
            if await model.finish() { onFinish(destination) }
        }
    }
}
