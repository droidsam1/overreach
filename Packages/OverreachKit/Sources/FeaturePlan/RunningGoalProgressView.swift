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
        .sheet(item: $selected) { row in RunningPainView(model: model, row: row) }
    }
}

private struct RunningPainView: View {
    let model: PlanModel
    let row: RunningGoalResultRow
    @State private var during: Bool?
    @State private var after: Bool?
    @Environment(\.dismiss) private var dismiss

    init(model: PlanModel, row: RunningGoalResultRow) {
        self.model = model
        self.row = row
        _during = State(initialValue: row.result.painDuring)
        _after = State(initialValue: row.result.painAfter)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                Section {
                    Picker("Pain during the run", selection: $during) { painAnswers }
                    Picker("Pain after the run", selection: $after) { painAnswers }
                } header: {
                    Text(row.date + " · " + row.summary)
                }
            }
            .navigationTitle("Pain report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await model.saveRunningPain(row, during: during, after: after) { dismiss() } }
                    }
                    .disabled(model.isSavingRunningPain)
                }
            }
        }
    }

    private var painAnswers: some View {
        Group {
            Text("Not sure").tag(nil as Bool?)
            Text("No").tag(Optional(false))
            Text("Yes").tag(Optional(true))
        }
    }
}
