import DesignSystem
import Domain
import SettingsPresentation
import SwiftUI
#if canImport(SafariServices) && os(iOS)
import SafariServices
#endif

/// Connecting Garmin in three steps (ADR-0022): what you get, create the key in Garmin Connect, paste it. Checking the
/// key, saving it in the Keychain and the first import happen on their own. Renders `GarminSetupModel`.
public struct GarminSetupView: View {
    @Bindable private var model: GarminSetupModel
    @State private var isShowingGarmin = false
    @State private var typedKey = ""
    @State private var appeared = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 72
    @ScaledMetric(relativeTo: .headline) private var instructionBadgeSize: CGFloat = 28

    public init(model: GarminSetupModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.large) {
                if let counter = model.stepCounterText {
                    VStack(spacing: Spacing.small) {
                        PageDots(count: 3, index: model.step.rawValue)
                            .accessibilityHidden(true)
                        Text(counter).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    content
                        .padding(.horizontal, Spacing.medium)
                        .id(model.step)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
                    .padding(.horizontal, Spacing.medium)
            }
            .padding(.vertical, Spacing.medium)
            .animation(reduceMotion ? nil : .spring(duration: 0.45), value: model.step)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.canGoBack {
                        Button("Back", systemImage: "chevron.left") { model.back() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.step != .syncing {
                        Button("Close") { model.finish() }
                    }
                }
            }
            .interactiveDismissDisabled(model.step == .syncing || model.isChecking)
        }
        #if canImport(SafariServices) && os(iOS)
        .sheet(isPresented: $isShowingGarmin) {
            if let url = GarminSetupModel.keyPageURL {
                SafariView(url: url).ignoresSafeArea()
            }
        }
        #endif
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch model.step {
        case .intro: intro
        case .createKey: createKey
        case .pasteKey: pasteKey
        case .syncing: syncing
        case .done: done
        }
    }

    private var intro: some View {
        VStack(spacing: Spacing.large) {
            hero("applewatch.radiowaves.left.and.right")
            Text("Connect Garmin")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Bring in what Apple Health doesn't get from your watch, so Today can judge your recovery better.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            card {
                FeatureHighlightRow(
                    symbol: "waveform.path.ecg", title: Text("Nightly HRV"),
                    detail: Text("With Garmin's baseline: the key signal for the readiness light.")
                )
                FeatureHighlightRow(
                    symbol: "bed.double.fill", title: Text("Sleep stages and score"),
                    detail: Text("Plus Body Battery, stress, SpO2 and respiration.")
                )
                FeatureHighlightRow(
                    symbol: "figure.run", title: Text("Runs and strength from the watch"),
                    detail: Text("Garmin load and training effect, matched with the sessions you log here.")
                )
            }
            privacyNote
        }
    }

    private var createKey: some View {
        VStack(spacing: Spacing.large) {
            hero("key.horizontal.fill")
            Text("Create your key")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Garmin gives each person a personal key to their own data. It takes a minute in Garmin Connect.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            card {
                instruction(1, "Sign in to Garmin Connect if it asks.")
                instruction(2, "Tap **Create Key** and accept the terms.")
                instruction(3, "Choose **1 year** as the expiry: one less thing to renew.")
                instruction(4, "Tap **Copy**, then **Done** to come back here.")
            }
            Label("The key is shown only once. Copy it before closing the page.", systemImage: "info.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var pasteKey: some View {
        VStack(spacing: Spacing.large) {
            hero(model.isChecking ? "checkmark.shield" : "doc.on.clipboard.fill")
            Text("Paste your key")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("The app checks it with Garmin, saves it in your Keychain and imports your last 60 days.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Spacing.small) {
                if typeSize.isAccessibilitySize {
                    lifetimePicker.pickerStyle(.menu)
                } else {
                    Text("Expiry you chose").font(.headline).accessibilityHidden(true)
                    lifetimePicker.pickerStyle(.segmented)
                }
                Text("Used only to remind you before the key expires.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.isChecking {
                ProgressView("Checking with Garmin…")
                    .padding(Spacing.medium)
            } else {
                VStack(spacing: Spacing.medium) {
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.first ?? ""
                        Task { await model.paste(pasted) }
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .labelStyle(.titleAndIcon)
                    AdaptiveStack {
                        TextField("Or type it here", text: $typedKey)
                            .accessibilityLabel(Text("Garmin key"))
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .submitLabel(.go)
                            .onSubmit { submitTypedKey() }
                        Button(action: submitTypedKey) {
                            Text("Connect")
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(typedKey.isEmpty)
                    }
                }
            }
            if let error = model.errorMessage {
                errorLabel(error)
            }
            privacyNote
        }
    }

    private var lifetimePicker: some View {
        Picker("Expiry you chose", selection: $model.lifetime) {
            Text("30 days").tag(GarminKeyLifetime.days30)
            Text("90 days").tag(GarminKeyLifetime.days90)
            Text("180 days").tag(GarminKeyLifetime.days180)
            Text("1 year").tag(GarminKeyLifetime.oneYear)
        }
        .disabled(!model.canPaste)
    }

    private var syncing: some View {
        VStack(spacing: Spacing.large) {
            hero("arrow.triangle.2.circlepath")
                .symbolEffect(.rotate, options: .repeating, isActive: !reduceMotion)
            Text("Key saved")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Group {
                if let progress = model.progress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                }
            }
            .accessibilityHidden(true)
            Group {
                if let progressText = model.progressText {
                    Text(progressText)
                } else {
                    Text("Importing your last 60 days…")
                }
            }
            .font(.headline).multilineTextAlignment(.center)
            Text("It takes a few seconds. You can keep this screen open.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var done: some View {
        VStack(spacing: Spacing.large) {
            hero(model.errorMessage == nil ? "checkmark.seal.fill" : "exclamationmark.arrow.triangle.2.circlepath")
            Text("Garmin connected")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let summary = model.summaryText {
                Text(summary).font(.title3).multilineTextAlignment(.center)
            }
            if let notice = model.driftNotice {
                Label(notice, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            if let error = model.errorMessage {
                errorLabel(error)
                Button("Try again", systemImage: "arrow.clockwise") {
                    Task { await model.sync() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isSyncing)
            }
            card {
                FeatureHighlightRow(
                    symbol: "arrow.triangle.2.circlepath", title: Text("Syncs on its own"),
                    detail: Text("Every time you open the app. You can also sync from Settings.")
                )
                FeatureHighlightRow(
                    symbol: "bell.badge", title: Text("Reminder before it expires"),
                    detail: Text("Settings tells you two weeks before; renewing takes the same three steps.")
                )
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        switch model.step {
        case .intro:
            primaryButton("Get started") { model.next() }
        case .createKey:
            VStack(spacing: Spacing.small) {
                primaryButton("Open Garmin Connect", systemImage: "arrow.up.forward.app") { openGarmin() }
                Button("I already have a key") { model.next() }
            }
        case .pasteKey:
            Button("Open Garmin Connect again", systemImage: "arrow.up.forward.app") { openGarmin() }
                .disabled(model.isChecking)
        case .syncing:
            EmptyView()
        case .done:
            primaryButton("Done") { model.finish() }
        }
    }

    // MARK: Pieces

    private func openGarmin() {
        model.openedGarmin()
        #if canImport(SafariServices) && os(iOS)
        isShowingGarmin = true
        #else
        if let url = GarminSetupModel.keyPageURL { openURL(url) }
        #endif
    }

    private func submitTypedKey() {
        let key = typedKey
        Task {
            await model.paste(key)
            if model.errorMessage == nil { typedKey = "" }
        }
    }

    private func hero(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: heroSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .symbolEffect(.bounce, options: .nonRepeating, value: model.step)
            .padding(.top, Spacing.medium)
            .accessibilityHidden(true)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.medium, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func instruction(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.medium) {
            Text(verbatim: "\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: instructionBadgeSize, height: instructionBadgeSize)
                .background(Circle().fill(.tint))
                .accessibilityHidden(true)
            Text(text)
        }
    }

    private var privacyNote: some View {
        Label(
            "Your key stays on your iPhone, in the Keychain, and only syncs through your own iCloud Keychain.",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func primaryButton(
        _ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
        }
        .buttonStyle(BrandButtonStyle())
    }
}

#if canImport(SafariServices) && os(iOS)
/// Garmin Connect inside the app, so "Done" brings the person straight back to the paste step.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
