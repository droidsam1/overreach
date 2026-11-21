import DesignSystem
import SwiftUI
import TodayPresentation

struct TodayReadinessDetails: View {
    let model: TodayModel

    var body: some View {
        DisclosureGroup("Why this recommendation?") {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(model.readinessLines, id: \.self) { line in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(line.text).font(.subheadline)
                            .foregroundStyle(line.kind == .unavailable ? .secondary : .primary)
                        if let source = line.source {
                            Text(line.evidence).font(.caption).foregroundStyle(.secondary)
                            Link("Research source", destination: source).font(.caption)
                        }
                        ReadingLinks(items: line.readings.map(ReadingLinkItem.init))
                    }
                }
                ForEach(model.readinessObservations, id: \.self) { observation in
                    Text(observation.text).font(.subheadline)
                        .foregroundStyle(observation.kind == .unavailable ? .secondary : .primary)
                }
                if let context = model.readinessTrainingContext {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(context.heading).font(.subheadline.weight(.medium))
                        ForEach(context.workouts.indices, id: \.self) { index in
                            Text(context.workouts[index]).font(.subheadline)
                        }
                    }
                }
                if let note = model.hrvCoverageNote {
                    Text(note).font(.subheadline).foregroundStyle(.secondary)
                }
                if !model.readinessSources.isEmpty {
                    ReadinessSources(model: model)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.small)
        }
    }
}

private struct ReadinessSources: View {
    let model: TodayModel

    var body: some View {
        DisclosureGroup("Data sources and coverage") {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(model.readinessSources) { source in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(source.title).font(.subheadline.weight(.medium))
                        ForEach(source.details, id: \.self) { detail in
                            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.small)
        }
    }
}

struct TodayMetrics: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: TodayModel

    private var columns: [GridItem] {
        [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 150), spacing: Spacing.medium)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            LazyVGrid(columns: columns, spacing: Spacing.medium) {
                if model.showsSleep {
                    MetricTile(title: "Sleep", value: model.sleepHours, unit: "h", fractionDigits: 1,
                               caption: model.sleepCaption ?? model.sleepAverageCaption)
                }
                if model.showsHRV {
                    MetricTile(title: "HRV", value: model.hrvMs, unit: "ms", caption: model.hrvCaption)
                }
                if model.showsRestingHeartRate {
                    MetricTile(title: "Resting HR", value: model.restingHeartRate, unit: "bpm",
                               caption: model.restingHeartRateCaption)
                }
                if model.showsSteps {
                    MetricTile(title: "Steps", value: model.steps, unit: "", caption: model.stepsCaption)
                }
                if model.showsBodyBattery {
                    MetricTile(title: "Body Battery", value: model.bodyBattery, unit: "",
                               caption: model.bodyBatteryCaption)
                }
                if model.showsStress {
                    MetricTile(title: "Stress", value: model.stress, unit: "", caption: model.stressCaption)
                }
                if model.showsVO2Max {
                    MetricTile(title: "VO2max", value: model.vo2Max, unit: "", fractionDigits: 1,
                               caption: model.vo2MaxCaption)
                }
            }

            if !model.readinessSources.isEmpty {
                ReadinessSources(model: model)
            }

            if let sources = model.sourcesText {
                Text(sources).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
