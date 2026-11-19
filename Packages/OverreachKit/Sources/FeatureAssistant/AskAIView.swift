import AssistantPresentation
import DesignSystem
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Views only: layout, styling and sharing. The data and texts come from `AssistantPresentation` (ADR-0014).

/// "Ask AI" (ADR-0017): shares the training context as raw data with ChatGPT, Claude or another chat app.
public struct AskAIView: View {
    @State private var model: AskAIModel
    @State private var didCopy = false

    public init(model: AskAIModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Form {
            Section {
                Text(
                    """
                    Share your training as data: sessions with notes, exercise settings, trends and health \
                    metrics. Then ask ChatGPT, Claude or another assistant whatever you need.
                    """
                )
                .foregroundStyle(.secondary)
            }
            Section("Data") {
                Picker("Period", selection: Binding(
                    get: { model.period },
                    set: { period in Task { await model.setPeriod(period) } }
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
            }
            Section {
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
            } footer: {
                Text("It goes after the data. You can change it or write your own in the chat.")
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Section {
                if let message = model.message {
                    ShareLink(item: message) {
                        Label("Share with an AI app", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        copy(message)
                    } label: {
                        if didCopy {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
                if let url = model.fileURL {
                    ShareLink(item: url) {
                        Label("Share as a file", systemImage: "doc")
                    }
                }
            } footer: {
                Text(
                    """
                    Your data only leaves the phone when you share it, and only with the app you choose. It \
                    includes your notes.
                    """
                )
            }
        }
        .navigationTitle("Ask AI")
        .task { await model.prepare() }
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        didCopy = true
    }
}
