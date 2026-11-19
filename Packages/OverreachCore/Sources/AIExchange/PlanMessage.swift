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
    /// Paths of fields the format does not have (e.g. `routines[0].reps`). Set by `PlanMessageReader`; they are
    /// ignored, and the user and the AI are told.
    public var ignoredFields: [String] = []

    private enum CodingKeys: String, CodingKey {
        case format, version, routines, exerciseSettings
    }

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

    /// Fields of each object, as in the schema. A test keeps them in line with `jsonSchema`.
    static let fields: [String: Set<String>] = [
        "plan": ["format", "version", "routines", "exerciseSettings"],
        "routine": ["id", "name", "focus", "exercises"],
        "exerciseSettings": ["exercise", "focus", "scheme", "incrementKg", "isMainLift"],
        "scheme": ["type", "sets", "minReps", "maxReps", "reps", "repBlocks", "targetRPE"],
    ]

    static let referenceURL = "https://github.com/droidsam1/overreach/blob/main/docs/ai-exchange.md"
    static let schemaURL = "https://github.com/droidsam1/overreach/blob/main/docs/schemas/overreach.plan.v1.schema.json"

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
        - Sets and reps per exercise go in "exerciseSettings", not in the routine.
        - Prescribe effort (targetRPE), not fixed loads: the app sets each load from my recent sessions.
        - Leave out anything that should not change.
        - If I send you a correction from Overreach, fix every point and send the whole JSON again.
        """
}
