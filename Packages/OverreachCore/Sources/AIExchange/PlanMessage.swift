import Foundation

/// Routines and exercise settings proposed by an AI assistant (ADR-0017): `overreach.plan`, field reference in
/// `docs/ai-exchange.md`, JSON Schema in `docs/schemas/overreach.plan.v1.schema.json` (`jsonSchema`). Every field is
/// optional when decoding, so a reply with a missing field can be explained instead of rejected as unreadable.
public struct PlanMessage: Codable, Hashable, Sendable {
    public static let formatName = "overreach.plan"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var routines: [RoutineProposal]?
    public var exerciseSettings: [SettingsProposal]?
    /// Training blocks in order, each with the routines it rotates through (issue #34).
    public var blocks: [BlockProposal]?
    /// First day of the first block, `YYYY-MM-DD`. Absent: the day of the import.
    public var startDate: String?
    /// Paths of fields the format does not have (e.g. `routines[0].reps`). Set by `PlanMessageReader`; they are
    /// ignored, and the user and the AI are told.
    public var ignoredFields: [String] = []

    private enum CodingKeys: String, CodingKey {
        case format, version, routines, exerciseSettings, blocks, startDate
    }

    /// A session template. `id` identifies it across replies, so importing a revised routine updates it.
    public struct RoutineProposal: Codable, Hashable, Sendable {
        public var id: String?
        public var name: String?
        public var focus: String?
        /// Exercise names from the catalog, in order.
        public var exercises: [String]?
        /// Sets and reps for exercises of this routine only, e.g. heavier work in a strength block.
        public var prescriptions: [PrescriptionProposal]?
        /// Optional time budget to check in the import preview.
        public var maxDurationMinutes: Int?
    }

    /// A scheme for one exercise of one routine. It wins over the exercise's own settings in that routine.
    public struct PrescriptionProposal: Codable, Hashable, Sendable {
        public var exercise: String?
        public var scheme: SchemeProposal?
    }

    /// A period with one focus that rotates through some routines.
    public struct BlockProposal: Codable, Hashable, Sendable {
        public var name: String?
        public var focus: String?
        public var weeks: Int?
        /// Routine ids (or names) of this plan or already in the app, in rotation order.
        public var routines: [String]?
        /// Strength sessions planned each week; absent = one per routine.
        public var sessionsPerWeek: Int?
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

    /// Fields of each object, as in the schema. A test keeps them in line with `jsonSchema`.
    static let fields: [String: Set<String>] = [
        "plan": ["format", "version", "routines", "exerciseSettings", "blocks", "startDate"],
        "routine": ["id", "name", "focus", "exercises", "prescriptions", "maxDurationMinutes"],
        "prescription": ["exercise", "scheme"],
        "block": ["name", "focus", "weeks", "routines", "sessionsPerWeek"],
        "exerciseSettings": ["exercise", "focus", "scheme", "incrementKg", "isMainLift"],
        "scheme": ["type", "sets", "minReps", "maxReps", "reps", "repBlocks", "targetRPE"],
    ]

    static let referenceURL = "https://github.com/droidsam1/overreach/blob/main/docs/ai-exchange.md"
    static let schemaURL = "https://github.com/droidsam1/overreach/blob/main/docs/schemas/overreach.plan.v1.schema.json"
}

extension PlanMessage {
    /// JSON Schema (draft 2020-12) of `overreach.plan` v1. The same text is published in
    /// `docs/schemas/overreach.plan.v1.schema.json`; a test keeps both identical and in line with the validation.
    public static let jsonSchema = """
        {
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://github.com/droidsam1/overreach/blob/main/docs/schemas/overreach.plan.v1.schema.json",
          "title": "overreach.plan v1",
          "description": "Routines and exercise settings for the Overreach app. Exercise names must come from the catalog of the Overreach context.",
          "type": "object",
          "required": [
            "format",
            "version"
          ],
          "additionalProperties": false,
          "properties": {
            "format": {
              "const": "overreach.plan"
            },
            "version": {
              "const": 1
            },
            "routines": {
              "type": "array",
              "items": {
                "$ref": "#/$defs/routine"
              }
            },
            "exerciseSettings": {
              "type": "array",
              "items": {
                "$ref": "#/$defs/exerciseSettings"
              }
            },
            "blocks": {
              "type": "array",
              "description": "Training blocks in order. Each starts when the previous one ends.",
              "items": {
                "$ref": "#/$defs/block"
              }
            },
            "startDate": {
              "type": "string",
              "format": "date",
              "description": "First day of the first block (YYYY-MM-DD). Absent: the day of the import."
            }
          },
          "$defs": {
            "focus": {
              "enum": [
                "strength",
                "hypertrophy",
                "mixed",
                "endurance"
              ]
            },
            "reps": {
              "type": "integer",
              "minimum": 1,
              "maximum": 50
            },
            "routine": {
              "type": "object",
              "required": [
                "name",
                "exercises"
              ],
              "additionalProperties": false,
              "properties": {
                "id": {
                  "type": "string",
                  "minLength": 1,
                  "description": "Stable key: keep it when revising the routine."
                },
                "name": {
                  "type": "string",
                  "minLength": 1
                },
                "focus": {
                  "$ref": "#/$defs/focus"
                },
                "exercises": {
                  "type": "array",
                  "minItems": 1,
                  "items": {
                    "type": "string",
                    "minLength": 1
                  }
                },
                "maxDurationMinutes": {
                  "type": "integer",
                  "minimum": 1,
                  "maximum": 1440,
                  "description": "Optional session time limit in minutes, checked in the import preview."
                },
                "prescriptions": {
                  "type": "array",
                  "description": "Sets and reps for exercises of this routine only, instead of exerciseSettings.",
                  "items": {
                    "$ref": "#/$defs/prescription"
                  }
                }
              }
            },
            "prescription": {
              "type": "object",
              "required": [
                "exercise",
                "scheme"
              ],
              "additionalProperties": false,
              "properties": {
                "exercise": {
                  "type": "string",
                  "minLength": 1,
                  "description": "One of the routine's exercises."
                },
                "scheme": {
                  "$ref": "#/$defs/scheme"
                }
              }
            },
            "block": {
              "type": "object",
              "required": [
                "focus",
                "weeks"
              ],
              "additionalProperties": false,
              "properties": {
                "name": {
                  "type": "string",
                  "minLength": 1
                },
                "focus": {
                  "$ref": "#/$defs/focus"
                },
                "weeks": {
                  "type": "integer",
                  "minimum": 1,
                  "maximum": 52
                },
                "routines": {
                  "type": "array",
                  "description": "Routine ids (or names) trained in this block, in rotation order.",
                  "items": {
                    "type": "string",
                    "minLength": 1
                  }
                },
                "sessionsPerWeek": {
                  "type": "integer",
                  "minimum": 1,
                  "maximum": 14,
                  "description": "Strength sessions planned each week. Absent: one per routine."
                }
              }
            },
            "exerciseSettings": {
              "type": "object",
              "required": [
                "exercise"
              ],
              "additionalProperties": false,
              "properties": {
                "exercise": {
                  "type": "string",
                  "minLength": 1
                },
                "focus": {
                  "$ref": "#/$defs/focus"
                },
                "scheme": {
                  "$ref": "#/$defs/scheme"
                },
                "incrementKg": {
                  "type": "number",
                  "minimum": 0,
                  "maximum": 20
                },
                "isMainLift": {
                  "type": "boolean"
                }
              }
            },
            "scheme": {
              "type": "object",
              "required": [
                "type",
                "sets"
              ],
              "additionalProperties": false,
              "properties": {
                "type": {
                  "enum": [
                    "doubleProgression",
                    "linearLoad",
                    "repCycle",
                    "rpeBased"
                  ]
                },
                "sets": {
                  "type": "integer",
                  "minimum": 1,
                  "maximum": 10
                },
                "minReps": {
                  "$ref": "#/$defs/reps"
                },
                "maxReps": {
                  "$ref": "#/$defs/reps"
                },
                "reps": {
                  "$ref": "#/$defs/reps"
                },
                "repBlocks": {
                  "type": "array",
                  "minItems": 1,
                  "items": {
                    "$ref": "#/$defs/reps"
                  }
                },
                "targetRPE": {
                  "type": "number",
                  "minimum": 5,
                  "maximum": 10,
                  "default": 8,
                  "description": "Reps-in-reserve scale: 8 means about 2 reps left."
                }
              },
              "allOf": [
                {
                  "if": {
                    "properties": {
                      "type": {
                        "const": "doubleProgression"
                      }
                    }
                  },
                  "then": {
                    "required": [
                      "minReps",
                      "maxReps"
                    ]
                  }
                },
                {
                  "if": {
                    "properties": {
                      "type": {
                        "enum": [
                          "linearLoad",
                          "rpeBased"
                        ]
                      }
                    }
                  },
                  "then": {
                    "required": [
                      "reps"
                    ]
                  }
                },
                {
                  "if": {
                    "properties": {
                      "type": {
                        "const": "repCycle"
                      }
                    }
                  },
                  "then": {
                    "required": [
                      "repBlocks"
                    ]
                  }
                }
              ]
            }
          }
        }
        """

    /// What the user pastes into the chat when they want routines or settings back: the schema, an example and the
    /// rules. Shown before it is copied; the user decides when to send it.
    public static let formatGuide = """
        When I ask you to create or change routines or exercise settings for my Overreach app, reply with one JSON \
        code block that validates against this JSON Schema (overreach.plan v1). Use only the fields in the schema: \
        anything else is ignored. Reference: \(referenceURL)

        ```json
        \(jsonSchema)
        ```

        Example:

        ```json
        {
          "format": "overreach.plan",
          "version": 1,
          "routines": [
            {
              "id": "upper-a",
              "name": "Upper A",
              "focus": "strength",
              "exercises": ["Bench Press (Barbell)", "Bent Over Row (Barbell)"],
              "prescriptions": [
                {
                  "exercise": "Bench Press (Barbell)",
                  "scheme": { "type": "rpeBased", "sets": 5, "reps": 3, "targetRPE": 8 }
                }
              ]
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
          ],
          "startDate": "2027-01-04",
          "blocks": [
            { "name": "Strength", "focus": "strength", "weeks": 6, "routines": ["upper-a"], "sessionsPerWeek": 3 }
          ]
        }
        ```

        Rules:
        - Use exercise names exactly as in the "catalog" of my Overreach context.
        - "id" identifies a routine. Keep it when you revise that routine, so importing again updates it.
        - Sets and reps per exercise go in "exerciseSettings". Use a routine's "prescriptions" only when that \
        routine needs different sets and reps (e.g. a strength block).
        - For a multi-week plan, list "blocks" in order; each one rotates through its routines.
        - Prescribe effort (targetRPE), not fixed loads: the app sets each load from my recent sessions.
        - If I give a session time limit, set "maxDurationMinutes" on each affected routine.
        - Leave out anything that should not change.
        - If I send you a correction from Overreach, fix every point and send the whole JSON again.
        """
}
