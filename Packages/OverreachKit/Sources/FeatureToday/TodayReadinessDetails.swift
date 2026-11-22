import DesignSystem
import SwiftUI
import TodayPresentation

struct TodayReadinessDetails: View {
    let model: TodayModel
    var startsExpanded = false
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Reasons", isExpanded: $isExpanded) {
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
        .onAppear { if startsExpanded { isExpanded = true } }
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
