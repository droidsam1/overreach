import Domain
import PlanPresentation
import SwiftUI

struct HybridCalendarView: View {
    let model: PlanModel
    @State private var runEditor: RunningCalendarDraft?
    @State private var strengthEditor: StrengthCalendarDraft?

    init(model: PlanModel) { self.model = model }

    var body: some View {
        List {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Section("Upcoming training days") {
                if model.upcomingCalendarRows.isEmpty {
                    Text("No upcoming training days.").foregroundStyle(.secondary)
                }
                rows(model.upcomingCalendarRows)
            }
            if !model.pastCalendarRows.isEmpty {
                Section("Past training days") { rows(model.pastCalendarRows) }
            }
        }
        .navigationTitle("Hybrid calendar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add strength day", systemImage: "dumbbell") { strengthEditor = model.editStrengthEntry() }
                    if model.showsRunningCalendar {
                        Button("Add running day", systemImage: "figure.run") { runEditor = model.editRunningEntry() }
                    }
                } label: {
                    Label("Add training day", systemImage: "plus")
                }
            }
        }
        .task { await model.loadCalendarRoutines() }
        .sheet(item: $runEditor) { draft in
            RunningCalendarEntryView(model: model, draft: draft)
        }
        .sheet(item: $strengthEditor) { draft in
            StrengthCalendarEntryView(model: model, draft: draft)
        }
    }

    private func rows(_ rows: [HybridCalendarRow]) -> some View {
        ForEach(rows) { row in
            switch row {
            case let .run(run):
                Button { runEditor = model.editRunningEntry(run.entry) } label: {
                    rowLabel(title: run.title, date: run.date, status: run.status, symbol: "figure.run")
                }
            case let .strength(strength):
                Button { strengthEditor = model.editStrengthEntry(strength.entry) } label: {
                    rowLabel(title: strength.title, date: strength.date, status: nil, symbol: "dumbbell")
                }
            }
        }
    }

    private func rowLabel(title: String, date: String, status: String?, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(date).font(.footnote).foregroundStyle(.secondary)
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: symbol)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StrengthCalendarEntryView: View {
    let model: PlanModel
    @State private var draft: StrengthCalendarDraft
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoval = false

    init(model: PlanModel, draft: StrengthCalendarDraft) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                Picker("Routine", selection: $draft.routineID) {
                    Text("Strength rest day").tag(nil as UUID?)
                    ForEach(model.strengthRoutineOptions(for: draft)) { option in
                        Text(option.name).tag(Optional(option.value))
                    }
                }
                if !draft.isNew {
                    Button("Remove strength day", role: .destructive) { confirmRemoval = true }
                        .disabled(model.isSavingProfile)
                }
            }
            .navigationTitle("Strength day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await model.saveStrengthEntry(draft) { dismiss() } } }
                        .disabled(!model.canSaveStrengthEntry(draft))
                }
            }
            .confirmationDialog("Remove this planned day?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove strength day", role: .destructive) {
                    Task { if await model.removeStrengthEntry(draft.id) { dismiss() } }
                }
            }
        }
    }
}
