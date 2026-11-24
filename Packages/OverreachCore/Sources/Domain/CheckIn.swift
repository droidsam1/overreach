import Foundation

/// The user's daily subjective check-in (about 10 seconds to fill in).
public struct CheckIn: Hashable, Codable, Sendable {
    public struct Context: Hashable, Codable, Sendable {
        public enum Answer: String, Codable, Sendable { case yes, no, unsure, skipped }

        public let question: Question
        public let answer: Answer

        public init(question: Question, answer: Answer) {
            self.question = question
            self.answer = answer
        }
    }

    public enum LegResponse: String, Codable, Sendable {
        case normal, heavy, limited, notWarmedUp, skipped
    }

    public var day: CalendarDay
    public var isSick: Bool
    /// 1 (exhausted) … 5 (great).
    public var energy: Int?
    /// 0 (none) … 3 (very sore).
    public var soreness: Int?
    public var note: String?
    public var context: Context?
    public var legResponse: LegResponse?
    /// The athlete reports a symptom such as chest discomfort, unusual breathlessness or dizziness.
    public var exerciseWarningSigns: Bool?

    public init(
        day: CalendarDay, isSick: Bool = false, energy: Int? = nil, soreness: Int? = nil, note: String? = nil,
        context: Context? = nil, exerciseWarningSigns: Bool? = nil, legResponse: LegResponse? = nil
    ) {
        self.day = day
        self.isSick = isSick
        self.energy = energy
        self.soreness = soreness
        self.note = note
        self.context = context
        self.legResponse = legResponse
        self.exerciseWarningSigns = exerciseWarningSigns
    }
}

extension CheckIn.Context {
    public enum Question: String, Codable, Sendable { case symptoms, stress, fatigue, runningPain }
}
