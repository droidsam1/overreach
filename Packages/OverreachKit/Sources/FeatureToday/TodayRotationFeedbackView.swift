import DesignSystem
import PresentationKit
import SwiftUI
import TodayPresentation

struct TodayRotationFeedbackView: View {
    let model: TodayModel

    var body: some View {
        let feedback = model.rotationFeedback
        Form {
            Section {
                Toggle("Review rotation suggestions", isOn: Binding(
                    get: { feedback.isEnabled }, set: { feedback.setEnabled($0) }
                ))
            } footer: {
                Text("Records stay on this device. Turning this off clears them.")
            }
            ForEach(feedback.recentEntries) { entry in
                Section { record(entry, feedback: feedback) }
            }
        }
        .navigationTitle("Review rotation suggestions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func record(_ entry: RotationFeedback.Entry, feedback: RotationFeedback) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(entry.id.kind.title).font(.subheadline.weight(.semibold))
            Text(model.rotationFeedbackDate(entry.id.day))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let choice = entry.choice {
                Text(choice.title).font(.subheadline)
            }
            Menu {
                ForEach(RotationFeedback.Usefulness.allCases, id: \.self) { usefulness in
                    Button(usefulness.title) { feedback.rate(usefulness, for: entry.id) }
                }
            } label: {
                Text(entry.usefulness?.title ?? L10n.text("Was this useful?"))
            }
            if entry.id.kind != .warmUpQuestion {
                Menu {
                    ForEach(RotationFeedback.Outcome.allCases, id: \.self) { outcome in
                        Button(outcome.title) { feedback.report(outcome, for: entry.id) }
                    }
                } label: {
                    Text(entry.outcome?.title ?? L10n.text("How did training go?"))
                }
            }
        }
    }
}
