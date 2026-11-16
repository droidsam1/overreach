import DesignSystem
import Domain
import SwiftUI
import UniformTypeIdentifiers

/// Settings. Phase 1: import from Strong. Later: connections (Health, Garmin), readiness thresholds, report
/// template, backup, and in phase 4 the AI provider, model and API key.
public struct SettingsView: View {
    @State private var importModel: ImportModel
    @State private var isPickingFile = false

    public init(importModel: ImportModel) {
        _importModel = State(initialValue: importModel)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Weights in the file", selection: $importModel.weightUnit) {
                        Text("kg").tag(WeightUnit.kilograms)
                        Text("lb").tag(WeightUnit.pounds)
                    }
                    .onChange(of: importModel.weightUnit) {
                        Task { await importModel.refreshPreview() }
                    }
                    Button("Choose Strong CSV…", systemImage: "square.and.arrow.down") { isPickingFile = true }
                    importStatus
                } header: {
                    Text("Import from Strong")
                } footer: {
                    Text("In Strong: Settings → Export data. Re-importing the same file does not create duplicates.")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text]
            ) { result in
                guard case let .success(url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                Task { await importModel.load(fileData: data) }
            }
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
