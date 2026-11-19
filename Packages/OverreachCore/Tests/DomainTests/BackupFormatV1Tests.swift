import Domain
import Foundation
import Testing

/// What a format-1 backup looks like, with every type and field the app stored when v1 shipped (ADR-0018).
///
/// **Never edit this fixture.** It stands for backups and stores that already exist on users' devices. If a test
/// here fails, a change broke them: make the new field optional or decode it with a default (`decodeIfPresent`),
/// or raise the format version and add a migration step in `BackupCodec.migrate`.
@Suite("Backup format 1 stays readable")
struct BackupFormatV1Tests {
    static let fixture = #"""
        {
          "appVersion" : "0.1.0",
          "checkIns" : [
            {
              "day" : {
                "day" : 21,
                "month" : 9,
                "year" : 2026
              },
              "energy" : 3,
              "isSick" : false,
              "note" : "Tired",
              "soreness" : 2
            }
          ],
          "createdAt" : 811700000,
          "exercises" : [
            {
              "aliases" : [
                "Hip thrust"
              ],
              "equipment" : "machine",
              "id" : "00000000-0000-4000-8000-000000000001",
              "isCustom" : true,
              "name" : "Hip Thrust (Machine)",
              "primaryMuscles" : [
                "glutes"
              ],
              "secondaryMuscles" : [
                "hamstrings"
              ]
            }
          ],
          "formatVersion" : 1,
          "profile" : {
            "birthYear" : 1990,
            "bodyMassKg" : 80.5,
            "cycleTracking" : "off",
            "declaredBlocks" : [
              {
                "focus" : "strength",
                "isDeclared" : true,
                "plannedWeeks" : 6,
                "start" : {
                  "day" : 1,
                  "month" : 11,
                  "year" : 2026
                }
              }
            ],
            "effortScale" : "repsInReserve",
            "goal" : {
              "kind" : "strength",
              "priorityLifts" : [
                "00000000-0000-4000-8000-000000000001"
              ],
              "targetDate" : {
                "day" : 1,
                "month" : 3,
                "year" : 2027
              }
            },
            "maxHeartRate" : 190,
            "restingHeartRate" : 52,
            "sex" : "male",
            "walkingRoutine" : {
              "canRunDuringWalks" : false,
              "flexibleSplit" : true,
              "hasDog" : true,
              "usualWalksPerDay" : 2,
              "walksAreFixed" : false
            }
          },
          "progressionSettings" : [
            {
              "exerciseID" : "00000000-0000-4000-8000-000000000001",
              "settings" : {
                "focus" : "hypertrophy",
                "incrementKg" : 2.5,
                "isMainLift" : true,
                "scheme" : {
                  "doubleProgression" : {
                    "maxReps" : 12,
                    "minReps" : 8,
                    "sets" : 3,
                    "targetRPE" : 8.5
                  }
                }
              }
            },
            {
              "exerciseID" : "00000000-0000-4000-8000-000000000002",
              "settings" : {
                "incrementKg" : 1.25,
                "isMainLift" : false,
                "scheme" : {
                  "repCycle" : {
                    "repBlocks" : [
                      12,
                      8,
                      5
                    ],
                    "sets" : 4,
                    "targetRPE" : 8
                  }
                }
              }
            },
            {
              "exerciseID" : "00000000-0000-4000-8000-000000000003",
              "settings" : {
                "incrementKg" : 2.5,
                "isMainLift" : false,
                "scheme" : {
                  "linearLoad" : {
                    "reps" : 5,
                    "sets" : 5,
                    "targetRPE" : 8
                  }
                }
              }
            },
            {
              "exerciseID" : "00000000-0000-4000-8000-000000000004",
              "settings" : {
                "focus" : "strength",
                "incrementKg" : 0,
                "isMainLift" : false,
                "scheme" : {
                  "rpeBased" : {
                    "reps" : 4,
                    "sets" : 4,
                    "targetRPE" : 8
                  }
                }
              }
            }
          ],
          "routines" : [
            {
              "exerciseIDs" : [
                "00000000-0000-4000-8000-000000000001"
              ],
              "focus" : "strength",
              "id" : "00000000-0000-4000-8000-000000000030",
              "name" : "Push A"
            }
          ],
          "sessions" : [
            {
              "entries" : [
                {
                  "countsForProgression" : true,
                  "exerciseID" : "00000000-0000-4000-8000-000000000001",
                  "id" : "00000000-0000-4000-8000-000000000021",
                  "sets" : [
                    {
                      "distanceMeters" : 0,
                      "durationSeconds" : 30,
                      "id" : "00000000-0000-4000-8000-000000000022",
                      "kind" : "working",
                      "reps" : 5,
                      "weightKg" : 100
                    }
                  ]
                }
              ],
              "id" : "00000000-0000-4000-8000-000000000020",
              "name" : "Legs",
              "source" : "strongImport",
              "startedAt" : 811606400
            },
            {
              "endedAt" : 811696400,
              "entries" : [
                {
                  "countsForProgression" : true,
                  "exerciseID" : "00000000-0000-4000-8000-000000000001",
                  "id" : "00000000-0000-4000-8000-000000000011",
                  "notes" : "Felt strong",
                  "sets" : [
                    {
                      "completedAt" : 811693100,
                      "id" : "00000000-0000-4000-8000-000000000012",
                      "kind" : "warmup",
                      "reps" : 5,
                      "weightKg" : 40
                    },
                    {
                      "completedAt" : 811693400,
                      "id" : "00000000-0000-4000-8000-000000000013",
                      "kind" : "working",
                      "reps" : 8,
                      "rpe" : 8.5,
                      "weightKg" : 80
                    }
                  ]
                },
                {
                  "countsForProgression" : false,
                  "exerciseID" : "00000000-0000-4000-8000-000000000001",
                  "id" : "00000000-0000-4000-8000-000000000014",
                  "sets" : [
                    {
                      "id" : "00000000-0000-4000-8000-000000000015",
                      "kind" : "dropSet",
                      "reps" : 6,
                      "rpe" : 9,
                      "weightKg" : 60
                    }
                  ]
                }
              ],
              "focus" : "strength",
              "id" : "00000000-0000-4000-8000-000000000010",
              "name" : "Push A",
              "notes" : "Slept badly",
              "sessionRPE" : 8,
              "source" : "app",
              "startedAt" : 811692800
            }
          ]
        }
        """#

    private func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!  // swiftlint:disable:this force_unwrapping
    }

    private func decoded() throws -> BackupDocument {
        try BackupCodec.decode(Data(Self.fixture.utf8))
    }

    @Test func everySectionLoads() throws {
        let document = try decoded()
        #expect(document.formatVersion == 1)
        #expect(document.appVersion == "0.1.0")
        #expect(document.sessions.count == 2)
        #expect(document.exercises.count == 1)
        #expect(document.checkIns.count == 1)
        #expect(document.progressionSettings.count == 4)
        #expect(document.routines.count == 1)
    }

    @Test func sessionsKeepEveryDetail() throws {
        let session = try #require(try decoded().sessions.first { $0.id == id(10) })
        #expect(session.name == "Push A")
        #expect(session.notes == "Slept badly")
        #expect(session.sessionRPE == 8)
        #expect(session.focus == .strength)
        #expect(session.source == .app)
        #expect(session.durationSeconds == 3_600)
        #expect(session.entries.map(\.countsForProgression) == [true, false])
        #expect(session.entries[0].notes == "Felt strong")
        #expect(session.entries[0].sets.map(\.kind) == [.warmup, .working])
        #expect(session.entries[0].sets[1].rpe == 8.5)
        #expect(session.entries[1].sets.first?.kind == .dropSet)

        let imported = try #require(try decoded().sessions.first { $0.id == id(20) })
        #expect(imported.source == .strongImport)
        #expect(imported.entries.first?.sets.first?.durationSeconds == 30)
    }

    @Test func exercisesProfileAndSettingsKeepEveryDetail() throws {
        let document = try decoded()
        let exercise = try #require(document.exercises.first)
        #expect(exercise.isCustom)
        #expect(exercise.aliases == ["Hip thrust"])
        #expect(exercise.secondaryMuscles == [.hamstrings])
        #expect(exercise.equipment == .machine)

        let profile = document.profile
        #expect(profile.effortScale == .repsInReserve)
        #expect(profile.goal?.priorityLifts == [id(1)])
        #expect(profile.goal?.targetDate == CalendarDay(year: 2027, month: 3, day: 1))
        #expect(profile.declaredBlocks.first?.plannedWeeks == 6)
        #expect(profile.walkingRoutine.hasDog)
        #expect(profile.bodyMassKg == 80.5)

        let schemes = document.progressionSettings.map(\.settings.scheme)
        #expect(schemes == [
            .doubleProgression(sets: 3, minReps: 8, maxReps: 12, targetRPE: 8.5),
            .repCycle(sets: 4, repBlocks: [12, 8, 5], targetRPE: 8),
            .linearLoad(sets: 5, reps: 5, targetRPE: 8),
            .rpeBased(sets: 4, reps: 4, targetRPE: 8),
        ])
        #expect(document.progressionSettings.first?.settings.focus == .hypertrophy)
        #expect(document.progressionSettings.first?.settings.isMainLift == true)
        #expect(document.routines.first?.exerciseIDs == [id(1)])
        #expect(document.checkIns.first?.note == "Tired")
    }

    @Test func itRoundTripsWithTheCurrentEncoder() throws {
        let document = try decoded()
        #expect(try BackupCodec.decode(try BackupCodec.encode(document)) == document)
    }

    @Test func newerFormatsAreRefusedAndOlderOnesNeedAStep() throws {
        let newer = Self.fixture.replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 2")
        #expect(throws: BackupError.newerFormat(2)) { try BackupCodec.decode(Data(newer.utf8)) }
        let older = Self.fixture.replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 0")
        #expect(throws: BackupError.notABackup) { try BackupCodec.decode(Data(older.utf8)) }
    }

    @Test func sectionsAddedLaterAreOptional() throws {
        let minimal = #"{"formatVersion": 1, "createdAt": 0}"#
        let document = try BackupCodec.decode(Data(minimal.utf8))
        #expect(document.sessions.isEmpty)
        #expect(document.routines.isEmpty)
        #expect(document.profile == AthleteProfile())
    }
}
