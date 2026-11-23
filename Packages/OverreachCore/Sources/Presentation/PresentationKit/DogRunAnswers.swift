import Domain
import Observation

/// Device-local companion answers shared by Today and History.
@MainActor
@Observable
public final class DogRunAnswers {
    public struct Key: Hashable, Codable, Sendable {
        public let source: DataSourceKind
        public let activityID: String

        public init(source: DataSourceKind, activityID: String) {
            self.source = source
            self.activityID = activityID
        }

        public init(_ run: RunActivity) {
            self.init(source: run.source, activityID: run.id)
        }
    }

    private var values: [Key: Bool]
    private let save: @MainActor ([Key: Bool]) -> Void

    public init(_ values: [Key: Bool] = [:], save: @escaping @MainActor ([Key: Bool]) -> Void = { _ in }) {
        self.values = values
        self.save = save
    }

    public func answer(for key: Key, linked pair: RunMatchPair?) -> Bool? {
        values[key] ?? mirror(of: key, in: pair).flatMap { values[$0] }
    }

    public func record(_ withDog: Bool, for key: Key, linked pair: RunMatchPair?) {
        values[key] = withDog
        if let mirror = mirror(of: key, in: pair) { values[mirror] = withDog }
        save(values)
    }

    private func mirror(of key: Key, in pair: RunMatchPair?) -> Key? {
        guard let pair else { return nil }
        switch key.source {
        case .garmin: return Key(source: .appleHealth, activityID: pair.appleHealthID)
        case .appleHealth: return Key(source: .garmin, activityID: pair.garminID)
        default: return nil
        }
    }
}
