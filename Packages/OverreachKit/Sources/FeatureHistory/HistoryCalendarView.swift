import DesignSystem
import HistoryPresentation
import SwiftUI

// Views only: the grid, totals, texts and selection come from `HistoryCalendarModel` (ADR-0014).

/// History as a month calendar: strength days, runs and steps, with the selected day below.
struct HistoryCalendarView: View {
    @Bindable var history: HistoryModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fitsGrid = true
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var calendar: HistoryCalendarModel { history.calendar }

    private var showsAgenda: Bool { typeSize.isAccessibilitySize || !fitsGrid }

    var body: some View {
        List {
            Section {
                header
                if !showsAgenda {
                    grid
                    legend
                }
            }
            if !showsAgenda, let detail = calendar.selectedDetail {
                Section(detail.title) {
                    DayDetailRows(history: history, detail: detail)
                }
            }
            if showsAgenda {
                agenda
            }
            Section {
                totals
            } footer: {
                notices
            }
        }
        // Seven 44-pt cells plus the grouped list's outer margins.
        .onGeometryChange(for: Bool.self) { $0.size.width >= 352 } action: { fitsGrid = $0 }
        .animation(reduceMotion ? nil : .snappy, value: calendar.selectedDay)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: calendar.month)
        .listRowInsets(EdgeInsets(top: Spacing.small, leading: 0, bottom: Spacing.small, trailing: 0))
        .listRowSeparator(.hidden)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                previousMonth
                Spacer(minLength: 0)
                monthTitle
                Spacer(minLength: 0)
                nextMonth
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                monthTitle
                HStack {
                    previousMonth
                    nextMonth
                }
            }
        }
        .buttonStyle(.borderless)
        .listRowSeparator(.hidden)
    }

    private var monthTitle: some View {
        Text(calendar.monthTitle)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private var previousMonth: some View {
        Button {
            Task { await calendar.showPreviousMonth() }
        } label: {
            Label("Previous month", systemImage: "chevron.left")
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var nextMonth: some View {
        Button {
            Task { await calendar.showNextMonth() }
        } label: {
            Label("Next month", systemImage: "chevron.right")
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!calendar.canShowNextMonth)
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.medium) { legendItems }
            VStack(alignment: .leading, spacing: Spacing.xSmall) { legendItems }
        }
    }

    @ViewBuilder private var legendItems: some View {
        CalendarLegendItem("Strength", marker: .square(ActivityColor.strength))
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

    private var agenda: some View {
        Section("Activity by day") {
            let days = calendar.agendaDays
            if days.isEmpty {
                Text("No activity recorded this month.")
                    .foregroundStyle(.secondary)
            }
            ForEach(days) { cell in
                Button {
                    calendar.select(cell.day)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                        Text(cell.accessibilityLabel)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: cell.isSelected ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(cell.isSelected ? .isSelected : [])

                if cell.isSelected, let detail = calendar.selectedDetail {
                    DayDetailRows(history: history, detail: detail)
                }
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
private struct DayDetailRows: View {
    @Bindable var history: HistoryModel
    let detail: CalendarDayDetail

    var body: some View {
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
