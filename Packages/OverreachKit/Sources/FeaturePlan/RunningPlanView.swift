import PlanPresentation
import SwiftUI

struct RunningPlanView: View {
    @Bindable var model: PlanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Section {
                Toggle("Set a running goal", isOn: $model.runningDraft.enabled)
                if model.runningDraft.enabled {
                    TextField("Distance in km", value: $model.runningDraft.distanceKm, format: .number)
                    Toggle("Aim to run without pain", isOn: $model.runningDraft.aimsForPainFree)
                    Toggle("Set a target time", isOn: $model.runningDraft.hasTargetTime)
                    if model.runningDraft.hasTargetTime {
                        TextField("Target minutes", value: $model.runningDraft.targetMinutes, format: .number)
                        TextField("Target seconds", value: $model.runningDraft.targetSeconds, format: .number)
                        if let pace = model.runningGoalPace { Text(pace).foregroundStyle(.secondary) }
                    }
                }
            }
            if model.runningDraft.enabled {
                Section("Next planned run") {
                    Toggle("Add a planned day", isOn: $model.runningDraft.hasNextRun)
                    if model.runningDraft.hasNextRun {
                        DatePicker("Date", selection: $model.runningDraft.nextDate, displayedComponents: .date)
                        Picker("Session type", selection: $model.runningDraft.purpose) {
                            ForEach(model.runningSessionOptions) { option in
                                Text(option.name).tag(option.value)
                            }
                        }
                        if model.runningDraft.showsPlannedMinutes {
                            TextField("Planned minutes (0 if unknown)", value: $model.runningDraft.plannedMinutes,
                                      format: .number)
                        }
                    }
                }
            }
        }
        .navigationTitle("Running goal")
        .onAppear { model.resetRunningPlanEditor() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { if await model.saveRunningPlan() { dismiss() } }
                }
                .disabled(!model.canSaveRunningPlan)
            }
        }
    }
}
