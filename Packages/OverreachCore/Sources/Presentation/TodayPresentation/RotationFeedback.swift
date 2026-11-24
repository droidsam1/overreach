import Domain
import Foundation
import Observation
import PresentationKit

/// Prospective review records kept separately from the training profile and backups.
@MainActor
@Observable
public final class RotationFeedback {
    public enum Kind: String, Codable, Sendable {
        case swap, postpone, cap, warmUpQuestion

        public var title: String {
            switch self {
            case .swap: L10n.text("Swap sessions")
            case .postpone: L10n.text("Postpone session")
            case .cap: L10n.text("Keep today's lift lighter.")
            case .warmUpQuestion: L10n.text("Warm-up question")
            }
        }
    }

    public enum Choice: String, Codable, Sendable {
        case accepted, keptPlan, answered, skipped

        public var title: String {
            switch self {
            case .accepted: L10n.text("Accepted")
            case .keptPlan: L10n.text("Kept plan")
            case .answered: L10n.text("Answered")
            case .skipped: L10n.text("Skipped")
            }
        }
    }

    public enum Outcome: String, Codable, CaseIterable, Sendable {
        case completed, changed, noSession

        public var title: String {
            switch self {
            case .completed: L10n.text("Completed as chosen")
            case .changed: L10n.text("Changed during the session")
            case .noSession: L10n.text("Did not train")
            }
        }
    }

    public enum Usefulness: String, Codable, CaseIterable, Sendable {
        case useful, unnecessary

        public var title: String {
            switch self {
            case .useful: L10n.text("Useful")
            case .unnecessary: L10n.text("Unnecessary")
            }
        }
    }

    public struct EntryID: Codable, Hashable, Sendable {
        public let day: CalendarDay
        public let kind: Kind
    }

    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public let id: EntryID
        public fileprivate(set) var choice: Choice?
        public fileprivate(set) var usefulness: Usefulness?
        public fileprivate(set) var outcome: Outcome?
    }

    public struct State: Codable, Equatable, Sendable {
        var enabled = false
        var entries: [Entry] = []

        public init() {}
    }

    private static let retainedEntries = 30
    private var state: State
    private let save: @MainActor (State) -> Void

    public init(_ state: State = State(), save: @escaping @MainActor (State) -> Void = { _ in }) {
        self.state = state
        self.save = save
    }

    public var isEnabled: Bool { state.enabled }
    public var recentEntries: [Entry] { state.enabled ? Array(state.entries.reversed()) : [] }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != state.enabled else { return }
        state.enabled = enabled
        if !enabled { state.entries.removeAll() }
        save(state)
    }

    func shown(_ kind: Kind, on day: CalendarDay) {
        let id = EntryID(day: day, kind: kind)
        guard state.enabled, !state.entries.contains(where: { $0.id == id }) else { return }
        state.entries = Array((state.entries + [Entry(id: id)]).suffix(Self.retainedEntries))
        save(state)
    }

    func chose(_ choice: Choice, for kind: Kind, on day: CalendarDay) {
        edit(.init(day: day, kind: kind)) { $0.choice = choice }
    }

    public func rate(_ usefulness: Usefulness, for entry: EntryID) {
        edit(entry) { $0.usefulness = usefulness }
    }

    public func report(_ outcome: Outcome, for entry: EntryID) {
        guard entry.kind != .warmUpQuestion else { return }
        edit(entry) { $0.outcome = outcome }
    }

    private func edit(_ id: EntryID, update: (inout Entry) -> Void) {
        guard state.enabled, let index = state.entries.firstIndex(where: { $0.id == id }) else { return }
        let previous = state.entries[index]
        update(&state.entries[index])
        if state.entries[index] != previous { save(state) }
    }
}
