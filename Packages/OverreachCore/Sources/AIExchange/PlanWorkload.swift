import Analytics
import Domain
import Foundation

/// Estimates the prescribed workload before the plan is saved.
enum PlanWorkload {
    static let volumeEvidence = EvidenceReference(key: "volume-dose-response", level: .strong)
    static let deloadEvidence = EvidenceReference(key: "deload-design", level: .limited)
    static let timeEvidence = EvidenceReference(key: "plan-duration-estimate", level: .heuristic)

    private struct Workload {
        var seconds = 0.0
        var volume: [MuscleGroup: Double] = [:]
        var workingSets = 0.0
        var totalRPE = 0.0
    }

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
            let session = workload(change.routine, catalog: catalog, settings: effectiveSettings)
            guard session.seconds > Double(limit) * 60 else { return nil }
            let minutes = Int(min((session.seconds / 60).rounded(.up), Double(Int32.max)))
            return .sessionDuration(routine: change.routine.name, minutes: minutes, limit: limit)
        }
        var blockWarnings: [PlanWarning] = []
        var previous: (weeklySets: Double, averageRPE: Double)?
        for (proposal, block) in zip(message.blocks ?? [], planned.blocks) {
            let rotation = block.routineIDs.compactMap { routines[$0] }.map {
                workload($0, catalog: catalog, settings: effectiveSettings)
            }
            blockWarnings += volumeWarnings(block, rotation: rotation.map(\.volume))
            let current = weeklyEffort(rotation, sessions: block.plannedSessionsPerWeek)
            if proposal.isDeload == true, let previous, let current,
               current.weeklySets >= previous.weeklySets, current.averageRPE >= previous.averageRPE {
                blockWarnings.append(.unreducedDeload(block: block.name ?? block.focus.rawValue))
            }
            previous = current
        }
        return durationWarnings + blockWarnings
    }

    private static func workload(
        _ routine: Routine, catalog: [UUID: Exercise], settings: [UUID: ProgressionSettings]
    ) -> Workload {
        var result = Workload()
        for id in routine.exerciseIDs {
            guard let exercise = catalog[id] else { continue }
            let stored = settings[id]
            let focus = stored?.focus ?? routine.focus
            let prescription = routine.prescriptionDetails(for: id)
            let scheme = ProgressionTargets.settings(
                for: exercise, stored: stored, focus: focus, prescription: prescription?.scheme
            ).scheme
            let rest = prescription?.restSeconds ?? FocusPrescription.for(focus ?? .hypertrophy).defaultRestSeconds
            let sets = Double(scheme.sets)
            result.seconds += 30 * sets + Double(rest) * (sets - 1)
            result.workingSets += sets
            result.totalRPE += scheme.targetRPE * sets
            guard scheme.targetRPE >= StrengthMetrics.minimumEffectiveSetRPE else { continue }
            StrengthMetrics.addEffectiveSets(sets, for: exercise, to: &result.volume)
        }
        return result
    }

    private static func weeklyEffort(
        _ rotation: [Workload], sessions: Int
    ) -> (weeklySets: Double, averageRPE: Double)? {
        let sets = rotation.reduce(0) { $0 + $1.workingSets }
        guard sets > 0 else { return nil }
        let averageRPE = rotation.reduce(0) { $0 + $1.totalRPE } / sets
        return (sets * Double(sessions) / Double(rotation.count), averageRPE)
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
