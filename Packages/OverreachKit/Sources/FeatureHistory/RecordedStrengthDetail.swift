import DesignSystem
import HistoryPresentation
import SwiftUI

struct RecordedStrengthRow: View {
    let recording: HistoryStrengthActivity

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            AdaptiveStack {
                Text(recording.title).font(.headline)
                Spacer()
                Text(recording.startedAt, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(recording.subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecordedStrengthDetail: View {
    let recording: HistoryStrengthActivity

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
        }
        .navigationTitle(recording.title)
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
