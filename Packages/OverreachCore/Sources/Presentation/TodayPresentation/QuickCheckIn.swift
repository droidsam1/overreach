import Domain
import Foundation
import PresentationKit

/// The one-tap feeling scale of the pending check-in prompt. The values are the check-in's energy scale
/// (`CheckInModel.energyOptions`), so a tap stores exactly what the full sheet would.
@MainActor
enum QuickCheckIn {
    /// The answer that implies a follow-up: exhausted changes the decision, so the full check-in opens next.
    static let worst = 1

    static var options: [Option<Int>] { CheckInModel.energyScale }

    static func needsDetails(_ answer: Int) -> Bool { answer == worst }
}

extension TodayModel {
    /// "More: sleep, stress, pain…" opens the full check-in; its title sits next to the quick options.
    public var quickCheckInMoreTitle: String { L10n.text("More: sleep, stress, pain…") }

    func quickCheckInOptions() -> [Option<Int>] { QuickCheckIn.options }

    /// Saves the answer over today's check-in (every other field stays), then reloads so the verdict can change.
    func saveQuickCheckIn(_ answer: Int, now: Date) async {
        guard let sheet = makeCheckInModel(now: now), QuickCheckIn.options.contains(where: { $0.value == answer })
        else { return }
        sheet.energy = answer
        let saved = await sheet.save()
        // An unchanged answer has nothing to save; a failed save keeps the prompt as it was.
        guard saved || !sheet.canSave else { return }
        await load(now: now)
    }
}
