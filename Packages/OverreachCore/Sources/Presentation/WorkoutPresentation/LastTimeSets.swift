import Domain
import Foundation
import PresentationKit

/// The working sets of an exercise in its most recent saved session, shown as "Last time" next to today's target.
/// Unlike the progression history it includes entries left out of progression: it is what the athlete did.
struct LastTimeSets: Hashable, Codable, Sendable {
    struct Entry: Hashable, Codable, Sendable {
        let weightKg: Double?
        let reps: Int
        let rpe: Double?
    }

    let date: Date
    let sets: [Entry]

    /// The latest session in `sessions` with working sets of `exerciseID`; `nil` when there is none.
    static func latest(of exerciseID: UUID, in sessions: [StrengthSession]) -> Self? {
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            let sets = session.entries
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .compactMap { set -> Entry? in
                    guard set.isWorking, let reps = set.reps, reps > 0 else { return nil }
                    return Entry(weightKg: set.weightKg, reps: reps, rpe: set.rpe)
                }
            if !sets.isEmpty { return Self(date: session.startedAt, sets: sets) }
        }
        return nil
    }

    /// "60 kg × 8/8/7 @ RPE 8", "60 kg × 8/8 · 62.5 kg × 6" or "12/10/9"; the effort only when every set shares it.
    func text(effortScale: EffortScale, format: Format) -> String {
        var groups: [(weightKg: Double?, reps: [Int])] = []
        for set in sets {
            if let last = groups.last, last.weightKg == set.weightKg {
                groups[groups.count - 1].reps.append(set.reps)
            } else {
                groups.append((set.weightKg, [set.reps]))
            }
        }
        let text = groups.map { group in
            let reps = group.reps.map(String.init).joined(separator: "/")
            guard let weight = group.weightKg, weight > 0 else { return reps }
            return "\(format.weight(weight)) × \(reps)"
        }.joined(separator: " · ")
        guard let rpe = sets.first?.rpe, sets.allSatisfy({ $0.rpe == rpe }) else { return text }
        return "\(text) @ \(effortScale.text(rpe: rpe, format: format))"
    }
}
