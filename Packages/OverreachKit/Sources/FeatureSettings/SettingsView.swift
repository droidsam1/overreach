import DesignSystem
import Domain
import SettingsPresentation
import SwiftUI
import UniformTypeIdentifiers

/// Settings. Phase 1: backup and import from Strong. Later: connections (Health, Garmin), readiness
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

    @State private var importModel: ImportModel
    @State private var backupModel: BackupModel
    @State private var isPickingFile = false
    @State private var filePick: FilePick = .strongCSV
    @State private var exportURL: URL?
    private let library: Library

    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    public init(importModel: ImportModel, backupModel: BackupModel, @ViewBuilder library: () -> Library) {
        _importModel = State(initialValue: importModel)
        _backupModel = State(initialValue: backupModel)
        self.library = library()
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Library") { library }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                backupSection
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
                } header: {
                    Text("Import from Strong")
                } footer: {
                    Text("In Strong: Settings → Export data. Re-importing the same file does not create duplicates.")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: filePick.contentTypes) { result in
                handlePicked(result)
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: $backupModel.isConfirmingRestore,
                titleVisibility: .visible
            ) {
                Button("Restore") { Task { await backupModel.confirmRestore() } }
                Button("Cancel", role: .cancel) { backupModel.cancelRestore() }
            } message: {
                if let message = backupModel.pendingRestoreMessage {
                    Text(message)
                }
            }
            .task { await backupModel.load() }
            // Asked from the first-run setup ("Restore from a backup"); runs when Settings first appears too.
            .task(id: backupModel.isRequestingFolderChoice) {
                guard backupModel.isRequestingFolderChoice else { return }
                backupModel.isRequestingFolderChoice = false
                pick(.backupFolder)
            }
        }
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
            Button("Export…", systemImage: "square.and.arrow.up") {
                Task { exportURL = await backupModel.exportFile() }
            }
            if let exportURL {
                ShareLink(item: exportURL) { Label("Share \(exportURL.lastPathComponent)", systemImage: "doc") }
            }
            Button("Restore from file…", systemImage: "arrow.down.doc") { pick(.backupFile) }
            if let message = backupModel.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            if let warning = backupModel.backupWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
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
    public init(importModel: ImportModel, backupModel: BackupModel) {
        self.init(importModel: importModel, backupModel: backupModel) { EmptyView() }
    }
}
