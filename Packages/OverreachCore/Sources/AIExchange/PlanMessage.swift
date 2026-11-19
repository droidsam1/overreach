import Foundation

/// Routines and exercise settings proposed by an AI assistant (ADR-0017): `overreach.plan`, field reference in
/// `docs/ai-exchange.md`. Every field is optional when decoding, so a reply with a missing field can be explained
/// instead of rejected as unreadable.
public struct PlanMessage: Codable, Hashable, Sendable {
    public static let formatName = "overreach.plan"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var routines: [RoutineProposal]?
    public var exerciseSettings: [SettingsProposal]?

    /// A session template. `id` identifies it across replies, so importing a revised routine updates it.
    public struct RoutineProposal: Codable, Hashable, Sendable {
        public var id: String?
        public var name: String?
        public var focus: String?
        /// Exercise names from the catalog, in order.
        public var exercises: [String]?
    }

    /// How one exercise progresses. Absent fields keep their current value.
    public struct SettingsProposal: Codable, Hashable, Sendable {
        public var exercise: String?
        public var focus: String?
        public var scheme: SchemeProposal?
        public var incrementKg: Double?
        public var isMainLift: Bool?
    }

    public struct SchemeProposal: Codable, Hashable, Sendable {
        public var type: String?
        public var sets: Int?
        public var minReps: Int?
        public var maxReps: Int?
        public var reps: Int?
        public var repBlocks: [Int]?
        public var targetRPE: Double?
    }

    /// What the user pastes into the chat when they want routines or settings back: the format, an example and the
    /// rules. Shown before it is copied; the user decides when to send it.
    public static let formatGuide = """
        When I ask you to create or change routines or exercise settings for my Overreach app, reply with one JSON \
        code block in this format (overreach.plan v1, reference: \(referenceURL)):

        ```json
        {
          "format": "overreach.plan",
          "version": 1,
          "routines": [
            {
              "id": "upper-a",
              "name": "Upper A",
              "focus": "strength",
              "exercises": ["Bench Press (Barbell)", "Bent Over Row (Barbell)"]
            }
          ],
          "exerciseSettings": [
            {
              "exercise": "Bench Press (Barbell)",
              "focus": "strength",
              "scheme": { "type": "rpeBased", "sets": 4, "reps": 4, "targetRPE": 8 },
              "incrementKg": 2.5,
              "isMainLift": true
            }
          ]
        }
        ```

        Rules:
        - Use exercise names exactly as in the "catalog" of my Overreach context.
        - "id" identifies a routine. Keep it when you revise that routine, so importing again updates it.
        - "focus": strength, hypertrophy, mixed or endurance.
        - "scheme.type": doubleProgression (sets, minReps, maxReps, targetRPE), linearLoad (sets, reps, \
        targetRPE), repCycle (sets, repBlocks, targetRPE) or rpeBased (sets, reps, targetRPE). targetRPE uses the \
        reps-in-reserve scale: 8 means about 2 reps left.
        - Prescribe effort, not fixed loads: the app sets each load from my recent sessions.
        - Leave out anything that should not change.
        """

    static let referenceURL = "https://github.com/droidsam1/overreach/blob/main/docs/ai-exchange.md"
}
