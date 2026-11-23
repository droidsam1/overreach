import Domain
import SwiftUI
import TodayPresentation

/// Asks how a recorded run felt: pain during and after on a 0–10 scale, and whether it settled by morning (#256).
struct RunPainSheet: View {
    let model: TodayModel
    let prompt: RunPainPrompt
    @State private var during: Int?
    @State private var after: Int?
    @State private var settled: Bool?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(model: TodayModel, prompt: RunPainPrompt) {
        self.model = model
        self.prompt = prompt
        _during = State(initialValue: prompt.report.severityDuring)
        _after = State(initialValue: prompt.report.severityAfter)
        _settled = State(initialValue: prompt.report.settledByMorning)
    }

    private var hasPain: Bool { (during ?? 0) > 0 || (after ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if prompt.question == .severity {
                        Picker("Pain during the run", selection: $during) { severityAnswers }
                        Picker("Pain after the run", selection: $after) { severityAnswers }
                    }
                    if prompt.question == .settled || hasPain {
                        Picker("Gone by the next morning", selection: $settled) {
                            Text("Not sure").tag(nil as Bool?)
                            Text("No").tag(Optional(false))
                            Text("Yes").tag(Optional(true))
                        }
                    }
                } header: {
                    Text(prompt.summary)
                } footer: {
                    Text("0 is no pain and 10 is the worst you can imagine. Not medical advice.")
                }
            }
            .navigationTitle(Text(verbatim: prompt.title))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            let saved = await model.saveRunPain(
                                prompt, during: during, after: after, settledByMorning: settled)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(isSaving || (prompt.question == .severity && during == nil && after == nil))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var severityAnswers: some View {
        Group {
            Text("Not sure").tag(nil as Int?)
            ForEach(RunPainReport.scale, id: \.self) { Text(verbatim: "\($0)/10").tag(Optional($0)) }
        }
    }
}
