import Domain
import Foundation

/// Compares the strength work in a logged window or a planned rotation against the same thresholds (ADR-0047).
public enum MuscleBalance {
    public typealias Finding = MuscleBalanceFinding

    public struct Settings: Hashable, Sendable {
        public var windowWeeks = 4
        public var pullingWindowWeeks = 2
        public var hamstringWindowWeeks = 4
        public var minimumWeeklySets = 4.0
        public var minimumWeeklySetsByGoal: [TrainingGoal.Kind: Double] = [:]
        public var highWeeklySets = 22.0
        public var veryHighWeeklySets = 30.0
        public var highSessionSets = 11.0
        public var minimumPullToPushRatio = 0.75
        public var highWeeklyPushSets = 10.0
        public var minimumDirectDeltSets = 5.0
        public var highWeeklyQuadSets = 10.0
        public var laggingMedianShare = 0.45

        public init() {}
    }

    public static func findings(
        history sessions: [StrengthSession], exercises: [UUID: Exercise], profile: AthleteProfile, now: Date,
        runningKilometres: Double? = nil, settings: Settings = Settings(), calendar: Calendar = .current
    ) -> [Finding] {
        guard let input = history(
            sessions: sessions, exercises: exercises, now: now, runningKilometres: runningKilometres,
            settings: settings, calendar: calendar
        ) else { return [] }
        let block = FocusBalance.activeDeclaredBlock(in: profile, now: now, calendar: calendar)
        return findings(input: input, goal: profile.goal?.kind ?? .general, block: block, settings: settings)
    }

    public static func findings(
        plan block: TrainingBlock, routines: [Routine], exercises: [UUID: Exercise],
        exerciseSettings: [UUID: ProgressionSettings], profile: AthleteProfile, settings: Settings = Settings()
    ) -> [Finding] {
        guard let input = projection(
            block: block, routines: routines, exercises: exercises, exerciseSettings: exerciseSettings,
            settings: settings
        ) else { return [] }
        return findings(input: input, goal: profile.goal?.kind ?? .general, block: block, settings: settings)
    }

    public static func findings(
        input: Input, goal: TrainingGoal.Kind, block: TrainingBlock? = nil, settings: Settings = Settings()
    ) -> [Finding] {
        Audit(input: input, goal: goal, block: block, settings: settings).findings()
    }
}

private struct Audit {
    typealias Finding = MuscleBalance.Finding

    let input: MuscleBalance.Input
    let goal: TrainingGoal.Kind
    let block: TrainingBlock?
    let settings: MuscleBalance.Settings

    private var specialization: Set<MuscleGroup> {
        guard let block, block.isDeclared else { return [] }
        return block.specializedMuscles ?? []
    }

    private var weekly: MuscleBalance.SessionVolume { input.weekly }

    private var tracked: [MuscleGroup] {
        MuscleGroup.allCases.filter { muscle in
            muscle != .core && muscle != .forearms && !muscle.isLegacyAggregate
        }
    }

    private var pulling: [MovementPattern] { [.horizontalPull, .verticalPull] }

    func findings() -> [Finding] {
        guard weekly.hasUnmappedSets || weekly.fractionalSets.values.contains(where: { $0 > 0 }) else { return [] }
        let comparable = tracked.filter { !weekly.ambiguousMuscles.contains($0) }
        let typical = median(comparable.compactMap { weekly.fractionalSets[$0] }.filter { $0 > 0 })
        let muscleFindings = tracked.flatMap { findings(for: $0, typical: typical) }
        return muscleFindings + pushPullFindings() + missingPulls() + hamstringFindings() + emptyRegions()
    }

    private func findings(for muscle: MuscleGroup, typical: Double) -> [Finding] {
        let sets = weekly.fractionalSets[muscle, default: 0]
        let direct = weekly.directSets[muscle, default: 0]
        let largest = input.sessions.lazy.map { $0.fractionalSets[muscle, default: 0] }.max() ?? 0
        return shortfalls(for: muscle, sets: sets, direct: direct, typical: typical)
            + excess(for: muscle, weeklySets: sets, largestSession: largest)
    }

    private func shortfalls(for muscle: MuscleGroup, sets: Double, direct: Double, typical: Double) -> [Finding] {
        guard !weekly.hasUnmappedSets, !weekly.ambiguousMuscles.contains(muscle),
              !isIntentionalShortfall(muscle) else { return [] }
        var result: [Finding] = []
        if direct == 0 {
            result.append(finding(.noDirectWork, muscle: muscle, sets: direct))
        }
        let minimum = settings.minimumWeeklySetsByGoal[goal] ?? settings.minimumWeeklySets
        if sets > 0 && sets < minimum {
            result.append(finding(.lowVolume, muscle: muscle, sets: sets))
        }
        if sets >= minimum && sets < typical * settings.laggingMedianShare {
            result.append(finding(.laggingMuscle, muscle: muscle, sets: sets))
        }
        return result
    }

    private func excess(for muscle: MuscleGroup, weeklySets: Double, largestSession: Double) -> [Finding] {
        var result: [Finding] = []
        if weeklySets >= settings.veryHighWeeklySets {
            result.append(finding(.veryHighVolume, muscle: muscle, sets: weeklySets))
        } else if weeklySets >= settings.highWeeklySets && !specialization.contains(muscle) {
            result.append(finding(.highVolume, muscle: muscle, sets: weeklySets))
        }
        if largestSession > settings.highSessionSets {
            result.append(finding(.highSessionVolume, muscle: muscle, sets: largestSession))
        }
        return result
    }

    private func pushPullFindings() -> [Finding] {
        guard !weekly.hasUnmappedSets else { return [] }
        let pulled = pulling.reduce(0) { $0 + weekly.patternSets[$1, default: 0] }
        let hasPushSpecialization = !specialization.isDisjoint(with: [.chest, .frontDelts, .triceps])
        var result: [Finding] = []
        if !hasPushSpecialization && !weekly.hasUnclassifiedPulling
            && pulled < weekly.pushSets * settings.minimumPullToPushRatio {
            result.append(finding(.lowPullVolume, sets: pulled))
        }
        guard weekly.pushSets > settings.highWeeklyPushSets else { return result }
        for muscle in [MuscleGroup.sideDelts, .rearDelts]
            where !isIntentionalShortfall(muscle) && !weekly.ambiguousMuscles.contains(muscle) {
            let sets = weekly.directSets[muscle, default: 0]
            if sets < settings.minimumDirectDeltSets {
                result.append(finding(.lowDeltVolume, muscle: muscle, sets: sets))
            }
        }
        return result
    }

    private func missingPulls() -> [Finding] {
        guard let volume = input.pullingWindow, !volume.hasUnmappedSets, !volume.hasUnclassifiedPulling,
              specialization.isEmpty else { return [] }
        return pulling.compactMap { pattern in
            volume.patternSets[pattern, default: 0] == 0 ? finding(.missingPullPattern, pattern: pattern) : nil
        }
    }

    private func hamstringFindings() -> [Finding] {
        guard let volume = input.hamstringWindow, !volume.hasUnmappedSets, !isIntentionalShortfall(.hamstrings),
              volume.fractionalSets[.quadriceps, default: 0] >= settings.highWeeklyQuadSets,
              volume.directSets[.hamstrings, default: 0] == 0,
              volume.patternSets[.hinge, default: 0] == 0 else { return [] }
        return [finding(.noHamstringWork, muscle: .hamstrings, sets: 0)]
    }

    private func emptyRegions() -> [Finding] {
        guard !weekly.hasUnmappedSets else { return [] }
        return [Finding.Region.upper, .lower].compactMap { region in
            let bodyRegion: BodyRegion = region == .upper ? .upper : .lower
            let hasWork = weekly.fractionalSets.contains { muscle, sets in muscle.region == bodyRegion && sets > 0 }
            let intentionallyOmitted = !specialization.isEmpty && !specialization.contains { $0.region == bodyRegion }
            guard !hasWork, !intentionallyOmitted else { return nil }
            return finding(.emptyRegion, region: region, sets: 0)
        }
    }

    private func isIntentionalShortfall(_ muscle: MuscleGroup) -> Bool {
        !specialization.isEmpty && !specialization.contains(muscle)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
    }

    private func finding(
        _ rule: Finding.Rule, muscle: MuscleGroup? = nil, pattern: MovementPattern? = nil,
        region: Finding.Region? = nil, sets: Double? = nil
    ) -> Finding {
        let kilometres = input.runningKilometres.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let lowerBody = muscle?.region == .lower || region == .lower
        return Finding(
            rule: rule, muscle: muscle, pattern: pattern, region: region, measuredSets: sets,
            runningKilometres: lowerBody ? kilometres : nil, evidence: evidence(for: rule)
        )
    }

    private func evidence(for rule: Finding.Rule) -> EvidenceReference {
        switch rule {
        case .noDirectWork, .lowVolume: EvidenceReference(key: "muscle-balance-maintenance", level: .heuristic)
        case .highVolume, .veryHighVolume: EvidenceReference(key: "muscle-balance-volume", level: .limited)
        case .highSessionVolume: EvidenceReference(key: "muscle-balance-session-volume", level: .limited)
        case .lowPullVolume: EvidenceReference(key: "muscle-balance-push-pull", level: .heuristic)
        case .lowDeltVolume: EvidenceReference(key: "muscle-balance-delts", level: .heuristic)
        case .missingPullPattern: EvidenceReference(key: "muscle-balance-pulling-patterns", level: .heuristic)
        case .noHamstringWork: EvidenceReference(key: "muscle-balance-hamstrings", level: .limited)
        case .laggingMuscle: EvidenceReference(key: "muscle-balance-relative-volume", level: .heuristic)
        case .emptyRegion: EvidenceReference(key: "muscle-balance-regions", level: .heuristic)
        }
    }
}
