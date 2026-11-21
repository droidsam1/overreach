import DesignSystem
import SwiftUI
import TodayPresentation

struct DeloadProposalCard<SessionPreview: View>: View {
    let model: TodayModel
    let advice: DeloadAdvice
    let explanation: DeloadExplanation
    let recoveryHistory: (() -> AnyView)?
    @ViewBuilder let sessionPreview: () -> SessionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label(DeloadProposalText.title, systemImage: "arrow.down.right.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.isHeader)
            Text(explanation.summary).font(.subheadline)
            Button(DeloadProposalText.start) { Task { await model.acceptDeload() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button { Task { await model.postponeDeload() } } label: {
                Text(DeloadProposalText.postpone).frame(minHeight: 44)
            }
            NavigationLink {
                detail
            } label: {
                Text(DeloadProposalText.details).frame(minHeight: 44)
            }
        }
    }

    private var detail: some View {
        List {
            Section(DeloadProposalText.whyNow) {
                ForEach(explanation.trainingReasons, id: \.self) { reason in
                    Text(reason)
                }
                if !explanation.recoveryReasons.isEmpty {
                    Text(DeloadProposalText.supportingRecovery).font(.subheadline.weight(.semibold))
                    ForEach(explanation.recoveryReasons, id: \.self) { reason in
                        Text(reason)
                    }
                }
            }
            Section(DeloadProposalText.lastRest) {
                Text(explanation.lastRest)
                if let recoveryHistory {
                    NavigationLink {
                        recoveryHistory()
                    } label: {
                        Text(DeloadProposalText.history)
                    }
                }
            }
            Section(DeloadProposalText.whatChanges) {
                Text(advice.planText)
                DisclosureGroup(DeloadProposalText.session) {
                    sessionPreview()
                }
            }
            Section(DeloadProposalText.evidence) {
                ForEach(explanation.evidence) { line in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(line.text)
                        Text(line.level).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ReadingLinks(items: explanation.readings.map(ReadingLinkItem.init))
            }
        }
        .navigationTitle(DeloadProposalText.details)
        .navigationBarTitleDisplayMode(.inline)
    }
}
