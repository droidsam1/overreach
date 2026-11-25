import DesignSystem
import HistoryPresentation
import SwiftUI

struct HistoryRunRow: View {
    let run: HistoryRunActivity
    var showsDate = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "figure.run")
                .foregroundStyle(ActivityColor.run)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(run.title).font(.headline)
                if showsDate {
                    Text(run.startedAt, format: .dateTime.day().month().year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.small) { metrics }
                    VStack(alignment: .leading, spacing: Spacing.xSmall) { metrics }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                Text(run.sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metrics: some View {
        Text(run.distance)
        Text(run.duration)
        if let pace = run.pace {
            Text(pace)
        }
    }
}

public struct HistoryRunDetail: View {
    @Environment(\.dismiss) private var dismiss
    @State private var weather: [HistoryMetric] = []
    let run: HistoryRunActivity
    let history: HistoryModel

    public init(run: HistoryRunActivity, history: HistoryModel) {
        self.run = run
        self.history = history
    }

    public var body: some View {
        List {
            Section {
                LabeledContent("Date") {
                    Text(run.startedAt, format: .dateTime.weekday().day().month().year().hour().minute())
                }
                LabeledContent("Sources", value: run.sourceText)
            }
            Section {
                LabeledContent("Distance", value: run.distance)
                LabeledContent("Duration", value: run.duration)
                if let pace = run.pace {
                    LabeledContent("Pace", value: pace)
                }
                if let heartRate = run.heartRate {
                    LabeledContent("Average heart rate", value: heartRate)
                }
                ForEach(run.trainingMetrics) { metric in
                    LabeledContent(metric.label, value: metric.value)
                }
            }
            if !weather.isEmpty {
                Section {
                    ForEach(weather) { metric in
                        LabeledContent(metric.label, value: metric.value)
                    }
                } header: {
                    Text("Weather near the start")
                } footer: {
                    Text("Estimated hourly weather from OpenWeather")
                }
            }
            if !run.movementMetrics.isEmpty {
                Section("Running and walking") {
                    ForEach(run.movementMetrics) { metric in
                        LabeledContent(metric.label, value: metric.value)
                    }
                }
            }
            if let companion = history.runCompanion(for: run) {
                Section {
                    Menu {
                        Button("Yes") { history.answerRun(run, withDog: true) }
                        Button("No") { history.answerRun(run, withDog: false) }
                    } label: {
                        LabeledContent {
                            if let answer = companion.answer { Text(answer) }
                        } label: {
                            Label(companion.question, systemImage: "dog")
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            if let match = run.match {
                Section {
                    Button("Undo run link") {
                        history.chooseRunMatch(.separate, for: match)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(run.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: run.id) {
            let details = await history.weatherDetails(for: run)
            if !Task.isCancelled { weather = details }
        }
    }
}
