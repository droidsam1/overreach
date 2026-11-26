import AssistantPresentation
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// Views only: layout, styling and sharing. The data and texts come from `AssistantPresentation` (ADR-0014).

/// "Ask AI" (ADR-0017): shares the training context as raw data with ChatGPT, Claude or another chat app, and
/// brings the AI's routines and exercise settings back.
public struct AskAIView: View {
    @State private var model: AskAIModel
    @State private var importer: PlanImportModel
    @State private var didCopy = false
    @State private var didCopyFormat = false
    @State private var isPickingFile = false

    public init(model: AskAIModel, importer: PlanImportModel) {
        _model = State(initialValue: model)
        _importer = State(initialValue: importer)
    }

    public var body: some View {
        Form {
            Section {
                Picker("Period", selection: Binding(
                    get: { model.period },
                    set: { period in
                        didCopy = false
                        Task { await model.setPeriod(period) }
                    }
                )) {
                    ForEach(model.periodOptions) { option in
                        Text(option.name).tag(option.value)
                    }
                }
                if model.isPreparing {
                    ProgressView()
                } else if let summary = model.summary {
                    Text(summary).foregroundStyle(.secondary)
                }
                Picker("First request", selection: Binding(
                    get: { model.request },
                    set: { request in
                        model.setRequest(request)
                        didCopy = false
                    }
                )) {
                    Text("None").tag(StarterRequest?.none)
                    ForEach(model.requestOptions) { option in
                        Text(option.name).tag(StarterRequest?.some(option.value))
                    }
                }
                if model.request == .nextBlock {
                    TextField("Training availability", text: Binding(
                        get: { model.availability },
                        set: {
                            model.setAvailability($0)
                            didCopy = false
                        }
                    ))
                }
                Toggle("Include health data", isOn: Binding(
                    get: { model.includesHealth },
                    set: {
                        model.setIncludesHealth($0)
                        didCopy = false
                    }
                ))
                Toggle("Include cycle tracking setting", isOn: Binding(
                    get: { model.includesCycle },
                    set: {
                        model.setIncludesCycle($0)
                        didCopy = false
                    }
                ))
            } header: {
                Text("Prepare your report")
            } footer: {
                Text("It goes after the data. You can change it or write your own in the chat.")
            }
            if let message = model.errorMessage {
                InlineNotice(Text(message), tone: .critical) { Task { await model.prepare() } }
            }
            Section {
                if let message = model.message {
                    ShareLink(item: message) {
                        Label("Share with an AI app", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BrandButtonStyle())
                    Button {
                        copy(message)
                    } label: {
                        if didCopy {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Label("Copy report", systemImage: "doc.on.doc")
                        }
                    }
                }
                if let url = model.fileURL {
                    ShareLink(item: url) {
                        Label("Share as a file", systemImage: "doc")
                    }
                }
                if model.message != nil {
                    Button {
                        copyToClipboard(importer.formatGuide)
                        didCopyFormat = true
                    } label: {
                        if didCopyFormat {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Label("Copy the reply format", systemImage: "curlybraces")
                        }
                    }
                }
            } header: {
                Text("Share with an assistant")
            } footer: {
                Text(
                    """
                    Your data only leaves the phone when you share it, and only with the app you choose. It \
                    includes your notes.
                    """
                )
            }
            answerSection
        }
        .navigationTitle("Ask AI")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.prepare() }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json, .plainText, .text]) { result in
            readPicked(result)
        }
        .sheet(isPresented: $importer.isShowingPreview) {
            PlanImportPreviewView(model: importer)
        }
    }

    private var answerSection: some View {
        Section {
            PasteButton(payloadType: String.self) { [importer] texts in
                Task { @MainActor in await importer.read(pasted: texts) }
            }
            Button("Import reply file…", systemImage: "folder") { isPickingFile = true }
            if let result = importer.resultMessage {
                InlineNotice(Text(result), tone: .positive)
            }
            if let message = importer.errorMessage {
                InlineNotice(Text(message), tone: .critical)
            }
        } header: {
            Text("Import the reply")
        } footer: {
            Text(
                """
                When you want routines or exercise settings, paste the reply format into the chat. Then paste the \
                AI's answer here: you see every change before it is saved.
                """
            )
        }
    }

    private func readPicked(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result else {
            importer.fileCouldNotBeOpened()
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importer.fileCouldNotBeOpened()
            return
        }
        Task { await importer.read(fileData: data) }
    }

    private func copy(_ text: String) {
        copyToClipboard(text)
        didCopy = true
    }
}

/// What an AI answer would change, with the problems that block it and a correction to send back.
struct PlanImportPreviewView: View {
    let model: PlanImportModel
    @State private var didCopyCorrection = false

    var body: some View {
        NavigationStack {
            List {
                if let preview = model.preview {
                    if !preview.issues.isEmpty || !preview.warnings.isEmpty {
                        Section {
                            ForEach(preview.issues, id: \.self) { issue in
                                InlineNotice(Text(issue), tone: .critical)
                            }
                            ForEach(preview.warnings, id: \.self) { warning in
                                InlineNotice(Text(warning), tone: .caution)
                            }
                            if let correction = preview.correction {
                                Button {
                                    copyToClipboard(correction)
                                    didCopyCorrection = true
                                } label: {
                                    if didCopyCorrection {
                                        Label("Copied", systemImage: "checkmark")
                                    } else {
                                        Label("Copy the correction for the AI", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        } header: {
                            if preview.canImport {
                                Text("Worth checking")
                            } else {
                                Text("Needs fixing")
                            }
                        } footer: {
                            if preview.canImport {
                                Text("You can import it as it is, or send the correction and bring the new answer.")
                            } else {
                                Text("Paste the correction into the chat and bring the new answer. Nothing was saved.")
                            }
                        }
                    }
                    if !preview.routines.isEmpty {
                        Section("Routines") {
                            ForEach(preview.routines) { row in
                                ChangeRow(title: row.name, detail: row.detail, isUpdate: row.isUpdate)
                            }
                        }
                    }
                    if !preview.settings.isEmpty {
                        Section("Exercise settings") {
                            ForEach(preview.settings) { row in
                                ChangeRow(title: row.exercise, detail: row.detail, isUpdate: row.isUpdate)
                            }
                        }
                    }
                    if !preview.blocks.isEmpty {
                        Section {
                            ForEach(preview.blocks) { row in
                                ChangeRow(title: row.name, detail: row.detail, isUpdate: false)
                            }
                        } header: {
                            Text("Training blocks")
                        } footer: {
                            Text("Train shows each block's next session. Later planned blocks are replaced.")
                        }
                    }
                }
            }
            .navigationTitle("AI plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await model.confirm() } }
                        .disabled(!(model.preview?.canImport ?? false))
                }
            }
        }
    }
}

private struct ChangeRow: View {
    let title: String
    let detail: String
    let isUpdate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(title).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if isUpdate {
                        Text("Updates")
                    } else {
                        Text("New")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private func copyToClipboard(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #endif
}
