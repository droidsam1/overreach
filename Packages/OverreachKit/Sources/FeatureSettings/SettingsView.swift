import DesignSystem
import Domain
import SwiftUI
import UniformTypeIdentifiers

/// Settings. Phase 1: backup and import from Strong. Later: connections (Health, Garmin), readiness
/// thresholds, report template, and in phase 4 the AI provider, model and API key.
public struct SettingsView: View {
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

    public init(importModel: ImportModel, backupModel: BackupModel) {
        _importModel = State(initialValue: importModel)
        _backupModel = State(initialValue: backupModel)
    }

    public var body: some View {
        NavigationStack {
            Form {
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
                guard case let .success(url) = result else { return }
                handlePicked(url)
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: $backupModel.isConfirmingRestore,
                titleVisibility: .visible
            ) {
                Button("Restore") { Task { await backupModel.confirmRestore() } }
                Button("Cancel", role: .cancel) { backupModel.cancelRestore() }
            } message: {
                if let summary = backupModel.pendingRestore {
                    Text("\(summary.sessions) sessions from \(summary.createdAt.formatted(date: .abbreviated, time: .shortened)). "
                        + "Items are merged by id: nothing is duplicated.")
                }
            }
            .task { await backupModel.load() }
        }
    }

    private func pick(_ kind: FilePick) {
        filePick = kind
        isPickingFile = true
    }

    private func handlePicked(_ url: URL) {
        switch filePick {
        case .backupFolder:
            Task { await backupModel.chooseFolder(url) }
        case .strongCSV, .backupFile:
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            if filePick == .strongCSV {
                Task { await importModel.load(fileData: data) }
            } else {
                backupModel.prepareRestore(fileData: data)
            }
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
            if let last = backupModel.lastBackup {
                LabeledContent("Last backup", value: last.createdAt.formatted(date: .abbreviated, time: .shortened))
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
                if !preview.newExercises.isEmpty {
                    DisclosureGroup("New exercises: \(preview.newExercises.count)") {
                        ForEach(preview.newExercises) { exercise in
                            Text(exercise.name)
                        }
                        Text("They are added as custom exercises. Assign their muscles later so their volume counts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if !preview.skippedLines.isEmpty {
                    Text("\(preview.skippedLines.count) lines could not be read and will be skipped.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button("Import") { Task { await importModel.confirm() } }
                    .bold()
                Button("Cancel", role: .cancel) { importModel.reset() }
            }
        case .importing:
            HStack {
                ProgressView()
                Text("Importing…")
            }
        case let .done(sessions, sets):
            Label("Imported \(sessions) sessions and \(sets) sets.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
