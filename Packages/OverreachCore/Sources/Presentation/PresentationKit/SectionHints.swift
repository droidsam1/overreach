/// Device-local record of newly available sections. The first observation for each screen seeds its existing rows.
@MainActor
public final class SectionHints {
    public enum Screen: String, Codable, Hashable, Sendable {
        case today, recoveryProgress
    }

    public enum Section: String, Codable, Hashable, Sendable {
        case recovery, history, recentLoad, progress

        var title: String {
            switch self {
            case .recovery: L10n.text("Recovery")
            case .history: L10n.text("History")
            case .recentLoad: L10n.text("Recent load")
            case .progress: L10n.text("Progress")
            }
        }
    }

    public struct State: Codable, Sendable {
        var seeded: Set<Screen> = []
        var shown: Set<Section> = []

        public init() {}
    }

    private var state: State
    private let save: @MainActor (State) -> Void

    public init(_ state: State = State(), save: @escaping @MainActor (State) -> Void = { _ in }) {
        self.state = state
        self.save = save
    }

    public func update(_ available: [Section], on screen: Screen) -> [String] {
        let wasSeeded = !state.seeded.insert(screen).inserted
        let new = available.filter { state.shown.insert($0).inserted }
        if !wasSeeded || !new.isEmpty { save(state) }
        return wasSeeded ? new.map { L10n.format("New: {1}", $0.title) } : []
    }
}
