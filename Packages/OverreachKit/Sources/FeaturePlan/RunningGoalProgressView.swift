import Domain
import PlanPresentation
import SwiftUI

struct RunningGoalProgressView: View {
    let model: PlanModel
    @State private var selected: RunningGoalResultRow?

    init(model: PlanModel) { self.model = model }

    var body: some View {
        List {
            if let progress = model.runningGoalProgress {
                Section {
                    Text(progress.goal).font(.headline)
                    Text(progress.status).font(.subheadline)
                }
                Section("Linked runs") {
                    if progress.rows.isEmpty {
                        Text("Link a recorded run in the running calendar to see it here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(progress.rows) { row in
                        Button {
                            selected = row
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.date + " · " + row.summary).foregroundStyle(.primary)
                                Text(row.painStatus).font(.footnote).foregroundStyle(.secondary)
                                if row.meetsGoal {
                                    Label("Meets your goal", systemImage: "checkmark.circle")
                                        .font(.footnote)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .navigationTitle("Running goal progress")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $selected) { row in RunningPainView(model: model, row: row) }
    }
}

private struct RunningPainView: View {
    let model: PlanModel
    let row: RunningGoalResultRow
    @State private var during: Int?
    @State private var after: Int?
    @State private var settled: Bool?
    @Environment(\.dismiss) private var dismiss

    init(model: PlanModel, row: RunningGoalResultRow) {
        self.model = model
        self.row = row
        let result = row.result
        _during = State(initialValue: result.severityDuring ?? result.painDuring.map { $0 ? nil : 0 } ?? nil)
        _after = State(initialValue: result.severityAfter ?? result.painAfter.map { $0 ? nil : 0 } ?? nil)
        _settled = State(initialValue: result.settledByMorning)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                Section {
                    Picker("Pain during the run", selection: $during) { severityAnswers }
                    Picker("Pain after the run", selection: $after) { severityAnswers }
                    if (during ?? 0) > 0 || (after ?? 0) > 0 {
                        Picker("Gone by the next morning", selection: $settled) {
                            Text("Not sure").tag(nil as Bool?)
                            Text("No").tag(Optional(false))
                            Text("Yes").tag(Optional(true))
                        }
                    }
                } header: {
                    Text(row.date + " · " + row.summary)
                } footer: {
                    Text("0 is no pain and 10 is the worst you can imagine. Not medical advice.")
                }
            }
            .navigationTitle("Pain report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let saved = await model.saveRunningPain(
                                row, severityDuring: during, severityAfter: after, settledByMorning: settled)
                            if saved { dismiss() }
                        }
                    }
                    .disabled(model.isSavingRunningPain)
                }
            }
        }
    }

    private var severityAnswers: some View {
        Group {
            Text("Not sure").tag(nil as Int?)
            ForEach(RunPainReport.scale, id: \.self) { Text(verbatim: "\($0)/10").tag(Optional($0)) }
        }
    }
}
