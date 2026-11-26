import Analytics
import Domain
import Foundation

/// Estimates the prescribed workload before the plan is saved.
enum PlanWorkload {
    static let volumeEvidence = EvidenceReference(key: "volume-dose-response", level: .strong)
    static let timeEvidence = EvidenceReference(key: "plan-duration-estimate", level: .heuristic)

    static func warnings(
        for message: PlanMessage, planned: PlanImport, existing: [Routine], exercises: [Exercise],
        settings: [UUID: ProgressionSettings]
    ) -> [PlanWarning] {
        let catalog = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let routines = Dictionary(
            (existing + planned.routines.map(\.routine)).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }
        )
        let effectiveSettings = settings.merging(planned.settings.map { ($0.exercise.id, $0.settings) }) { _, new in
            new
        }
        let proposals = zip(message.routines ?? [], planned.routines)
        let durationWarnings: [PlanWarning] = proposals.compactMap { proposal, change in
            guard let limit = proposal.maxDurationMinutes else { return nil }
            let session = workload(change.routine, focus: nil, catalog: catalog, settings: effectiveSettings)
            guard session.seconds > Double(limit) * 60 else { return nil }
            let minutes = Int(min((session.seconds / 60).rounded(.up), Double(Int32.max)))
            return .sessionDuration(routine: change.routine.name, minutes: minutes, limit: limit)
        }
        return durationWarnings + planned.blocks.flatMap { block in
            let rotation = block.routineIDs.compactMap { routines[$0] }.map {
                workload($0, focus: block.focus, catalog: catalog, settings: effectiveSettings).volume
            }
            return volumeWarnings(block, rotation: rotation)
        }
    }

    private static func workload(
        _ routine: Routine, focus: TrainingFocus?, catalog: [UUID: Exercise], settings: [UUID: ProgressionSettings]
    ) -> (seconds: Double, volume: [MuscleGroup: Double]) {
        var seconds = 0.0
        var volume: [MuscleGroup: Double] = [:]
        for id in routine.exerciseIDs {
            guard let exercise = catalog[id] else { continue }
            let stored = settings[id]
            let focus = stored?.focus ?? routine.focus ?? focus
            let scheme = ProgressionTargets.settings(
                for: exercise, stored: stored, focus: focus, prescription: routine.prescription(for: id)
            ).scheme
            let rest = FocusPrescription.for(focus ?? .hypertrophy).defaultRestSeconds
            seconds += 30 * Double(scheme.sets) + Double(rest) * Double(scheme.sets - 1)
            guard scheme.targetRPE >= StrengthMetrics.minimumEffectiveSetRPE else { continue }
            StrengthMetrics.addEffectiveSets(Double(scheme.sets), for: exercise, to: &volume)
        }
        return (seconds, volume)
    }

    private static func volumeWarnings(_ block: TrainingBlock, rotation: [[MuscleGroup: Double]]) -> [PlanWarning] {
        guard !rotation.isEmpty else { return [] }
        let sessions = block.plannedSessionsPerWeek
        let guide = StallDetection.Thresholds().weeklySetRange.upperBound
        let weeks = block.plannedWeeks ?? 0
        var peak: [MuscleGroup: Double] = [:]
        var position = 0
        for _ in 0..<weeks {
            var total: [MuscleGroup: Double] = [:]
            for _ in 0..<sessions {
                for (muscle, sets) in rotation[position] {
                    total[muscle, default: 0] += sets
                }
                position = (position + 1) % rotation.count
            }
            for (muscle, sets) in total {
                peak[muscle] = max(peak[muscle, default: 0], sets)
            }
        }
        return MuscleGroup.allCases.compactMap { muscle in
            guard let sets = peak[muscle], sets > guide else { return nil }
            return .weeklyVolume(block: block.name ?? block.focus.rawValue, muscle: muscle, sets: sets, guide: guide)
        }
    }
}
