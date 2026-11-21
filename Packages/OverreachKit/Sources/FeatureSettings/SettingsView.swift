import DesignSystem
import Domain
import SettingsPresentation
import SwiftUI
import UniformTypeIdentifiers

/// Settings: Garmin connection, backup and import from Strong. Later: Health, readiness
/// thresholds, report template, and in phase 4 the AI provider, model and API key.
///
/// `Library` holds rows the App injects for other features (e.g. the exercise list), since a feature never
/// imports another feature.
public struct SettingsView<Library: View>: View {
    /// One file importer serves every picker (several `.fileImporter` modifiers on one view conflict).
    private enum FilePick {
        case strongCSV, backupFolder, backupFile

        var contentTypes: [UTType] {
            switch self {
            case .strongCSV: [.commaSeparatedText, .plainText, .text]
            case .backupFolder: [.folder]
            case .backupFile: [.json]
            }
        }
    }

    @Binding private var showsStrongImport: Bool
    @State private var importModel: ImportModel
    @State private var backupModel: BackupModel
    @State private var garminModel: GarminSetupModel
    @State private var trainingModel: TrainingPreferencesModel
    @State private var isConfirmingDisconnect = false
    @State private var isPickingFile = false
    @State private var filePick: FilePick = .strongCSV
    @State private var exportURL: URL?
    private let library: Library

    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    public init(
        importModel: ImportModel, backupModel: BackupModel, garminModel: GarminSetupModel,
        trainingModel: TrainingPreferencesModel, showsStrongImport: Binding<Bool> = .constant(false),
        @ViewBuilder library: () -> Library
    ) {
        _showsStrongImport = showsStrongImport
        _importModel = State(initialValue: importModel)
        _backupModel = State(initialValue: backupModel)
        _garminModel = State(initialValue: garminModel)
        _trainingModel = State(initialValue: trainingModel)
        self.library = library()
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Library") { library }
                trainingSection
                garminSection
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                backupSection
                Section {
                    NavigationLink {
                        strongImport
                    } label: {
                        Label("Import from Strong", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $showsStrongImport) {
                strongImport
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: $backupModel.isConfirmingRestore,
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) { Task { await backupModel.confirmRestore() } }
                Button("Cancel", role: .cancel) { backupModel.cancelRestore() }
            } message: {
                if let message = backupModel.pendingRestoreMessage {
                    Text(message)
                }
            }
            .task { await backupModel.load() }
            .task { await garminModel.load() }
            .task { await trainingModel.load() }
            .confirmationDialog(
                "Disconnect Garmin?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { Task { await garminModel.disconnect() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The key is removed from this iPhone and your iCloud Keychain. What was imported stays.")
            }
            // Asked from the first-run setup ("Restore from a backup"); runs when Settings first appears too.
            .task(id: backupModel.isRequestingFolderChoice) {
                guard backupModel.isRequestingFolderChoice else { return }
                backupModel.isRequestingFolderChoice = false
                pick(.backupFolder)
            }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: filePick.contentTypes) { result in
            handlePicked(result)
        }
    }

    private var strongImport: some View {
        Form {
            Section {
                Picker("Weights in the file", selection: $importModel.weightUnit) {
                    Text("kg").tag(WeightUnit.kilograms)
                    Text("lb").tag(WeightUnit.pounds)
                }
                .onChange(of: importModel.weightUnit) {
                    Task { await importModel.refreshPreview() }
                }
                Button("Choose Strong CSV…", systemImage: "square.and.arrow.down") { pick(.strongCSV) }
                importStatus
            } footer: {
                Text("In Strong: Settings → Export data. Re-importing the same file does not create duplicates.")
            }
        }
        .navigationTitle("Import from Strong")
    }

    private func pick(_ kind: FilePick) {
        filePick = kind
        isPickingFile = true
    }

    private func handlePicked(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result else {
            reportPickFailure()
            return
        }
        switch filePick {
        case .backupFolder:
            Task { await backupModel.chooseFolder(url) }
        case .strongCSV, .backupFile:
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                reportPickFailure()
                return
            }
            if filePick == .strongCSV {
                Task { await importModel.load(fileData: data) }
            } else {
                backupModel.prepareRestore(fileData: data)
            }
        }
    }

    private func reportPickFailure() {
        switch filePick {
        case .strongCSV: importModel.fileCouldNotBeOpened()
        case .backupFile: backupModel.fileCouldNotBeOpened()
        case .backupFolder: backupModel.folderCouldNotBeOpened()
        }
    }

    @ViewBuilder
    private var trainingSection: some View {
        Section {
            Toggle(
                "Count breaks as rest automatically",
                isOn: Binding(
                    get: { trainingModel.countsBreaksAutomatically },
                    set: { value in Task { await trainingModel.setCountsBreaksAutomatically(value) } }
                )
            )
            if let message = trainingModel.errorMessage {
                Text(message).foregroundStyle(.red)
            }
        } header: {
            Text("Training")
        } footer: {
            Text(
                """
                A week or more without lifting counts as rest for strength, and without running as rest for \
                running, so the next deload is suggested later. Turn off to confirm each break yourself.
                """
            )
        }
    }

    private var garminSection: some View {
        Section {
            if garminModel.isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let lastSync = garminModel.lastSyncText {
                    Text(lastSync).font(.footnote).foregroundStyle(.secondary)
                }
                if let expiry = garminModel.expiryText {
                    Text(expiry).font(.footnote).foregroundStyle(.secondary)
                }
                if let warning = garminModel.expiryWarning {
                    StatusLabel(title: warning, tone: .caution).font(.footnote)
                }
                if garminModel.isSyncing {
                    ProgressView(value: garminModel.progress?.fraction ?? 0) {
                        Text("Syncing…")
                    }
                } else {
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await garminModel.sync() }
                    }
                }
                if let summary = garminModel.summaryText {
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                }
                if let error = garminModel.errorMessage, !garminModel.isPresented {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
                }
                Button("Renew key", systemImage: "key.horizontal") { garminModel.start() }
                Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                    isConfirmingDisconnect = true
                }
            } else {
                Button {
                    garminModel.start()
                } label: {
                    FeatureHighlightRow(
                        symbol: "applewatch.radiowaves.left.and.right", title: Text("Connect Garmin"),
                        detail: Text("Nightly HRV, sleep score, Body Battery and more. Three steps.")
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Garmin")
        } footer: {
            Text("Uses Garmin's official Personal API with your own key. Not affiliated with Garmin.")
        }
    }

    private var backupSection: some View {
        Section {
            if let folder = backupModel.folderName {
                LabeledContent("Folder", value: folder)
            }
            Button(backupModel.isConfigured ? "Change folder…" : "Choose iCloud Drive folder…", systemImage: "folder") {
                pick(.backupFolder)
            }
            if let last = backupModel.lastBackupText {
                LabeledContent("Last backup", value: last)
            }
            Button("Back up now", systemImage: "arrow.up.doc") { Task { await backupModel.backUpNow() } }
                .disabled(!backupModel.isConfigured || backupModel.isWorking)
            Button("Export backup…", systemImage: "square.and.arrow.up") {
                Task { exportURL = await backupModel.exportFile() }
            }
            if let exportURL {
                ShareLink(item: exportURL) { Label("Share \(exportURL.lastPathComponent)", systemImage: "doc") }
            }
            Button("Restore backup…", systemImage: "arrow.down.doc") { pick(.backupFile) }
            if let message = backupModel.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            if let warning = backupModel.backupWarning {
                StatusLabel(title: warning, tone: .caution)
                    .font(.footnote)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Backs up after every session and when you leave the app. Keeps the last 14 days of copies.")
        }
    }

    @ViewBuilder
    private var importStatus: some View {
        switch importModel.state {
        case .idle:
            EmptyView()
        case .preview:
            if let preview = importModel.preview {
                LabeledContent("Sessions", value: "\(preview.sessions.count)")
                LabeledContent("Sets", value: "\(preview.setCount)")
                if !importModel.newExerciseNames.isEmpty {
                    DisclosureGroup("New exercises: \(importModel.newExerciseNames.count)") {
                        ForEach(importModel.newExerciseNames, id: \.self) { name in
                            Text(name)
                        }
                        Text("They are added as custom exercises. Assign their muscles later so their volume counts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if importModel.skippedLineCount > 0 {
                    Text("\(importModel.skippedLineCount) lines could not be read and will be skipped.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button("Import") { Task { await importModel.confirm() } }
                    .bold()
                Button("Cancel", role: .cancel) { importModel.reset() }
            }
        case .importing:
            if let progress = importModel.progress {
                ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                    Text("Importing… \(progress.done) of \(progress.total) sessions")
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Importing…")
                }
            }
        case let .done(sessions, sets):
            Label("Imported \(sessions) sessions and \(sets) sets.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if importModel.lastImportNewExercises > 0 {
                Text("\(importModel.lastImportNewExercises) new exercises need their muscles. Assign them in Exercises.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

extension SettingsView where Library == EmptyView {
    public init(importModel: ImportModel, backupModel: BackupModel, garminModel: GarminSetupModel) {
        self.init(importModel: importModel, backupModel: backupModel, garminModel: garminModel) { EmptyView() }
    }
}
