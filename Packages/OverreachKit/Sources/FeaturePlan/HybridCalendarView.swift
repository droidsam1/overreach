import DesignSystem
import Domain
import PlanPresentation
import SwiftUI

struct HybridCalendarView: View {
    let model: PlanModel
    @State private var runEditor: RunningCalendarDraft?
    @State private var strengthEditor: StrengthCalendarDraft?

    init(model: PlanModel) { self.model = model }

    var body: some View {
        let completedTraining = model.completedTrainingCalendarRows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                if let message = model.errorMessage {
                    InlineNotice(Text(message), tone: .critical)
                }
                if !model.weekDays.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            SectionHeader(Text("Your week"))
                            PlanWeekStrip(days: model.weekDays)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        SectionHeader(Text("Upcoming training days"))
                        if model.upcomingCalendarRows.isEmpty {
                            Text("No upcoming training days.").foregroundStyle(.secondary)
                        }
                        rows(model.upcomingCalendarRows)
                    }
                }
                if !completedTraining.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            SectionHeader(Text("Completed this week"))
                            ForEach(completedTraining) { session in
                                CalendarRowLabel(
                                    title: session.title, date: session.date, status: nil,
                                    symbol: session.symbol, isRest: false
                                )
                            }
                        }
                    }
                }
                if !model.pastCalendarRows.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            SectionHeader(Text("Past training days"))
                            rows(model.pastCalendarRows)
                        }
                    }
                }
            }
            .padding(Spacing.medium)
        }
        .navigationTitle("Hybrid calendar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        .calendarEditors(model: model, run: $runEditor, strength: $strengthEditor)
    }

    private func rows(_ rows: [HybridCalendarRow]) -> some View {
        CalendarRows(model: model, rows: rows, runEditor: $runEditor, strengthEditor: $strengthEditor)
            .buttonStyle(.plain)
    }
}

/// Dated sessions and rest days, each opening its editor (where the date can be moved). Shared by Plan's next
/// sessions and the full calendar.
struct CalendarRows: View {
    let model: PlanModel
    let rows: [HybridCalendarRow]
    @Binding var runEditor: RunningCalendarDraft?
    @Binding var strengthEditor: StrengthCalendarDraft?

    var body: some View {
        ForEach(rows) { row in
            switch row {
            case let .run(run):
                Button { runEditor = model.editRunningEntry(run.entry) } label: {
                    CalendarRowLabel(
                        title: run.title, date: run.date, status: run.status,
                        symbol: "figure.run", isRest: row.isRest, warning: run.ceilingWarning
                    )
                }
            case let .strength(strength):
                Button { strengthEditor = model.editStrengthEntry(strength.entry) } label: {
                    CalendarRowLabel(
                        title: strength.title, date: strength.date, status: nil,
                        symbol: "dumbbell", isRest: row.isRest
                    )
                }
            }
        }
    }
}

private struct CalendarRowLabel: View {
    let title: String
    let date: String
    let status: String?
    let symbol: String
    let isRest: Bool
    var warning: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(date).font(.footnote).foregroundStyle(.secondary)
                if isRest { Text("Planned rest").font(.footnote).foregroundStyle(.secondary) }
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                if let warning {
                    InlineNotice(Text(warning), tone: .caution)
                }
            }
        } icon: {
            IconTile(symbolName: isRest ? "bed.double" : symbol, color: .accentColor)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The editors the calendar rows open, as sheets.
    func calendarEditors(
        model: PlanModel, run: Binding<RunningCalendarDraft?>, strength: Binding<StrengthCalendarDraft?>
    ) -> some View {
        sheet(item: run) { draft in
            RunningCalendarEntryView(model: model, draft: draft)
        }
        .sheet(item: strength) { draft in
            StrengthCalendarEntryView(model: model, draft: draft)
        }
    }
}

struct StrengthCalendarEntryView: View {
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
                    InlineNotice(Text(message), tone: .critical)
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
