import Domain

extension PlannedStrength {
    public func displayName(routineName: String?) -> String {
        guard routineID != nil else { return L10n.text("Strength rest day") }
        return routineName.map { L10n.format("Strength · {1}", $0) } ?? L10n.text("Scheduled routine unavailable")
    }
}

extension PlannedRun {
    public func calendarTitle(format: Format = Format()) -> String {
        purpose == .rest ? L10n.text("Running rest day") : displayName(format: format)
    }
}
