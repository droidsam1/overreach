/// Decisions saved when reviewing recordings in History.
public struct ActivityMatchChoices: Sendable {
    public let runs: [RunMatchPair: RunMatchChoice]
    public let strength: [StrengthMatchPair: StrengthMatchChoice]

    public init(runs: [RunMatchPair: RunMatchChoice] = [:], strength: [StrengthMatchPair: StrengthMatchChoice] = [:]) {
        self.runs = runs
        self.strength = strength
    }
}
