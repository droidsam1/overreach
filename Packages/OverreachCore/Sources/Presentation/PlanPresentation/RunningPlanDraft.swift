import Domain
import Foundation
import PresentationKit

public struct RunningPlanDraft: Hashable, Sendable {
    public var enabled: Bool
    public var distanceKm: Double
    public var hasTargetTime: Bool
    public var targetMinutes: Int
    public var targetSeconds: Int
    public var aimsForPainFree: Bool

    init(goal: TrainingGoal?) {
        let running = goal?.running
        enabled = running != nil
        distanceKm = Double(running?.distanceMeters ?? 5_000) / 1_000
        hasTargetTime = running?.targetSeconds != nil
        let time = running?.targetSeconds ?? 30 * 60
        targetMinutes = time / 60
        targetSeconds = time % 60
        aimsForPainFree = running?.aimsForPainFree ?? false
    }

    var isValid: Bool {
        guard enabled else { return true }
        guard (0.1...1_000).contains(distanceKm) else { return false }
        if hasTargetTime {
            guard (0...1_440).contains(targetMinutes), (0...59).contains(targetSeconds),
                  targetMinutes > 0 || targetSeconds > 0 else { return false }
        }
        return true
    }

    var goal: RunningGoal? {
        guard enabled, isValid else { return nil }
        return RunningGoal(distanceMeters: Int((distanceKm * 1_000).rounded()),
                           targetSeconds: hasTargetTime ? targetMinutes * 60 + targetSeconds : nil,
                           aimsForPainFree: aimsForPainFree)
    }
}
