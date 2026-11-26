import DesignSystem
import PlanPresentation
import SwiftUI

struct PlanWeekStrip: View {
    let days: [PlanWeekDay]

    var body: some View {
        WeekStrip(days: days.map(Self.weekDay))
    }

    private static func weekDay(_ day: PlanWeekDay) -> WeekDay {
        let kind: WeekDayKind = switch day.kind {
        case .strengthDone: .strengthDone
        case .runDone: .runDone
        case .restLogged: .restLogged
        case .plannedStrength: .plannedStrength
        case .plannedRun: .plannedRun
        case .today: .today
        case .empty: .empty
        }
        return WeekDay(
            id: day.id.hashValue, initial: day.initial, kind: kind, accessibilityLabel: day.accessibilityLabel
        )
    }
}
