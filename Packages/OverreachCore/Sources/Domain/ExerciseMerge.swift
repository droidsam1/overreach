import Foundation

/// Merging one exercise into another, e.g. an imported "Press banca inclinado" into
/// "Incline Bench Press (Barbell)": history moves to the target and the source's names become the target's
/// aliases, so importing the same file again resolves to the target instead of re-creating the source.
public enum ExerciseMerge {
    /// The sessions that use `sourceID`, with those entries re-pointed to `targetID`. Sessions that don't use the
    /// source are left out, so only changed sessions need saving.
    public static func repoint(
        _ sessions: [StrengthSession],
        from sourceID: UUID,
        to targetID: UUID
    ) -> [StrengthSession] {
        sessions.compactMap { session in
            guard session.entries.contains(where: { $0.exerciseID == sourceID }) else { return nil }
            var changed = session
            for index in changed.entries.indices where changed.entries[index].exerciseID == sourceID {
                changed.entries[index].exerciseID = targetID
            }
            return changed
        }
    }

    /// The routines that use `sourceID`, now using `targetID` in its place (a routine that already had the target
    /// keeps it once, at its first position). Routines that don't use the source are left out.
    public static func repoint(_ routines: [Routine], from sourceID: UUID, to targetID: UUID) -> [Routine] {
        routines.compactMap { routine in
            guard routine.exerciseIDs.contains(sourceID) else { return nil }
            var changed = routine
            changed.setExercises(routine.exerciseIDs.map { $0 == sourceID ? targetID : $0 })
            return changed
        }
    }

    /// `target` with the source's name and aliases added to its aliases (the target's own name is not repeated).
    public static func absorbing(_ source: Exercise, into target: Exercise) -> Exercise {
        var merged = target
        let ownName = fold(target.name)
        for name in [source.name] + source.aliases.sorted() where fold(name) != ownName {
            if !merged.aliases.contains(where: { fold($0) == fold(name) }) {
                merged.aliases.insert(name)
            }
        }
        return merged
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
