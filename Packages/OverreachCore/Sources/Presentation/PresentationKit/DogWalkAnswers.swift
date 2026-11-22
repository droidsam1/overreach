import Domain
import Foundation
import Observation

/// Device-local companion answers shared by Today and History.
@MainActor
@Observable
public final class DogWalkAnswers {
    public private(set) var values: [WalkCompanionAnswer]
    private let save: @MainActor ([WalkCompanionAnswer]) -> Void

    public init(
        _ values: [WalkCompanionAnswer] = [], save: @escaping @MainActor ([WalkCompanionAnswer]) -> Void = { _ in }
    ) {
        self.values = values
        self.save = save
    }

    public func answer(_ walk: WalkBout, among walks: [WalkBout], withDog: Bool) {
        let keys = CompanionWalkMatching.answerKeys(for: walk, among: walks)
        values.removeAll { keys.contains($0.key) }
        values.append(contentsOf: keys.map { WalkCompanionAnswer(key: $0, withCompanion: withDog) })
        save(values)
    }

    public nonisolated static func question(for routine: WalkingRoutine) -> String {
        let name = routine.dogName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? L10n.text("With your dog?") : L10n.format("With {1}?", name)
    }
}
