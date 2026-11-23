import DesignSystem
import Domain
import SwiftUI
import TodayPresentation

/// The single secondary prompt on Today.
struct TodayPromptCard<Content: View>: View {
    let title: Text
    var detail: Text?
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .top, spacing: Spacing.small) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    title.font(.headline).accessibilityAddTraits(.isHeader)
                    if let detail {
                        detail.font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            content()
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Quick check-in · Light") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource(recentHRV: 43)], checkIns: PreviewCheckIns()))
        .preferredColorScheme(.light)
}

#Preview("Quick check-in · Dark") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource(recentHRV: 43)], checkIns: PreviewCheckIns()))
        .preferredColorScheme(.dark)
}

private actor PreviewCheckIns: CheckInRepository {
    private var entries: [CalendarDay: CheckIn] = [:]

    func checkIn(for day: CalendarDay) async throws -> CheckIn? { entries[day] }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] {
        entries.values.filter { range.contains($0.day) }
    }

    func save(_ checkIn: CheckIn) async throws { entries[checkIn.day] = checkIn }
}
#endif
