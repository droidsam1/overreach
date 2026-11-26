import DesignSystem
import PlanPresentation
import SwiftUI

struct RunningPlanView: View {
    @Bindable var model: PlanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let error = model.errorMessage {
                InlineNotice(Text(error), tone: .critical)
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
            if model.showsRunningCalendar {
                Section {
                    NavigationLink("Running goal progress") { RunningGoalProgressView(model: model) }
                }
            }
        }
        .navigationTitle("Running goal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
