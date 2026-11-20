import DesignSystem
import HistoryPresentation
import SwiftUI

struct RecordedStrengthRow: View {
    let recording: HistoryStrengthActivity

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(ActivityColor.strength)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(recording.title).font(.headline)
                Text(recording.startedAt, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(recording.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecordedStrengthDetail: View {
    let recording: HistoryStrengthActivity
    let model: HistoryModel
    @State private var editor: SessionEditorModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Date") {
                    Text(recording.startedAt, format: .dateTime.weekday().day().month().year().hour().minute())
                }
                LabeledContent("Duration") {
                    Text(
                        Duration.seconds(recording.durationSeconds),
                        format: .units(allowed: [.hours, .minutes], width: .abbreviated)
                    )
                }
            } footer: {
                Text(recording.subtitle)
            }
            RecordedStrengthMetrics(recording: recording)
            Section {
                Button("Log this workout", systemImage: "plus.circle.fill") {
                    editor = model.makeEditor(forRecording: recording.id)
                }
            } footer: {
                Text("Log it with its exercises and sets. The watch's heart rate and load are added to it.")
            }
        }
        .navigationTitle(recording.title)
        .sheet(item: $editor) { editor in
            SessionEditorView(model: editor) { saved in
                model.didSave(saved)
                dismiss()
            }
        }
    }
}

struct RecordedStrengthMetrics: View {
    let recording: HistoryStrengthActivity

    var body: some View {
        if !recording.metrics.isEmpty {
            Section(recording.source) {
                ForEach(recording.metrics) { metric in
                    LabeledContent(metric.label, value: metric.value)
                }
            }
        }
    }
}
