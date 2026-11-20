import DesignSystem
import HistoryPresentation
import SwiftUI

// Views only: the grid, totals, texts and selection come from `HistoryCalendarModel` (ADR-0014).

/// History as a month calendar: strength days, runs and steps, with the selected day below.
struct HistoryCalendarView: View {
    @Bindable var history: HistoryModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var calendar: HistoryCalendarModel { history.calendar }

    var body: some View {
        List {
            Section {
                header
                grid
                legend
            }
            Section {
                totals
            } footer: {
                notices
            }
            if let detail = calendar.selectedDetail {
                DayDetailSection(history: history, detail: detail)
            }
        }
        .animation(.snappy, value: calendar.selectedDay)
        .toolbar {
            Button("Today") {
                Task { await calendar.showToday() }
            }
        }
        .task { await calendar.load() }
        .refreshable { await calendar.load() }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(calendar.weekdays) { weekday in
                Text(weekday.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Spacing.xSmall)
                    .accessibilityLabel(weekday.name)
            }
            ForEach(calendar.cells) { cell in
                DayCellButton(cell: cell) { calendar.select(cell.day) }
            }
        }
        .id(calendar.month)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: calendar.month)
        .listRowSeparator(.hidden)
    }

    private var header: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") {
                Task { await calendar.showPreviousMonth() }
            }
            Spacer()
            Text(calendar.monthTitle)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Next month", systemImage: "chevron.right") {
                Task { await calendar.showNextMonth() }
            }
            .disabled(!calendar.canShowNextMonth)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.body.weight(.semibold))
        .listRowSeparator(.hidden)
    }

    private var legend: some View {
        ViewThatFits {
            HStack(spacing: Spacing.medium) { legendItems }
            VStack(alignment: .leading, spacing: Spacing.xSmall) { legendItems }
        }
    }

    @ViewBuilder private var legendItems: some View {
        CalendarLegendItem("Strength", marker: .dot(ActivityColor.strength))
        CalendarLegendItem("Run", marker: .dot(ActivityColor.run))
        CalendarLegendItem("Steps vs your average", marker: .ring(ActivityColor.steps))
    }

    private var totals: some View {
        AdaptiveStack(spacing: Spacing.small) {
            ForEach(calendar.totals) { total in
                CompactStat(value: total.value, label: total.label)
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if let message = calendar.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
        if let hint = calendar.healthHint {
            Label(hint, systemImage: "heart.text.square")
        }
    }
}

/// A tappable day of the grid; blanks keep their place but do nothing.
private struct DayCellButton: View {
    let cell: CalendarDayCell
    let action: () -> Void

    var body: some View {
        if cell.isBlank {
            day.hidden().accessibilityHidden(true)
        } else {
            Button(action: action) { day }
            .buttonStyle(.plain)
            .accessibilityLabel(cell.accessibilityLabel)
            .accessibilityAddTraits(cell.isSelected ? .isSelected : [])
        }
    }

    private var day: some View {
        CalendarDayView(
            number: cell.number, ringFraction: cell.stepsFraction, showsStrength: cell.hasStrength,
            showsRun: cell.hasRun, isToday: cell.isToday, isFuture: cell.isFuture, isSelected: cell.isSelected
        )
    }
}

/// The selected day: sessions (linking to their detail), runs and steps.
private struct DayDetailSection: View {
    @Bindable var history: HistoryModel
    let detail: CalendarDayDetail

    var body: some View {
        Section {
            if detail.isEmpty {
                Text(detail.emptyText)
                    .foregroundStyle(.secondary)
            }
            ForEach(detail.sessions) { summary in
                NavigationLink {
                    SessionDetailView(model: history, sessionID: summary.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(ActivityColor.strength)
                            .accessibilityHidden(true)
                        SessionRow(summary: summary)
                    }
                }
            }
            ForEach(detail.runs) { run in
                RunRow(run: run)
            }
            if let steps = detail.steps {
                Label(steps, systemImage: "shoeprints.fill")
                    .monospacedDigit()
                    .labelStyle(TintedIconLabelStyle(tint: ActivityColor.steps))
            }
        } header: {
            Text(detail.title)
        }
    }
}

private struct RunRow: View {
    let run: CalendarRunLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "figure.run")
                .foregroundStyle(ActivityColor.run)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(run.title).font(.headline)
                Text(run.source).font(.caption).foregroundStyle(.secondary)
                AdaptiveStack(spacing: Spacing.medium) {
                    Text(run.distance)
                    Text(run.duration)
                    if let pace = run.pace {
                        Text(pace)
                    }
                    if let heartRate = run.heartRate {
                        Label(heartRate, systemImage: "heart.fill")
                            .labelStyle(TintedIconLabelStyle(tint: .red))
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                ForEach(run.trainingMetrics) { metric in
                    LabeledContent(metric.label, value: metric.value)
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xSmall) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
