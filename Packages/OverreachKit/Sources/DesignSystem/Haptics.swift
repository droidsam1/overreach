import SwiftUI

/// The app's haptics, named by what happened rather than by the vibration (ADR-0041 rule 7: small feedback where
/// the action happens).
public enum Haptic: Sendable {
    /// A set, a rest or another step finished.
    case completed
    /// The screen switched mode, such as reordering.
    case modeChanged
    /// One option of a short list was picked, such as an answer on a scale.
    case selected

    var feedback: SensoryFeedback {
        switch self {
        case .completed: .success
        case .modeChanged: .impact
        case .selected: .selection
        }
    }
}

extension EnvironmentValues {
    /// Turns every `haptic(_:trigger:when:)` off, so one setting can silence them all.
    @Entry public var hapticsEnabled = true
}

extension View {
    /// Plays `haptic` when `trigger` changes and `when(old, new)` holds. The only way views play haptics, so
    /// `hapticsEnabled` silences them all.
    public func haptic<T: Equatable>(
        _ haptic: Haptic, trigger: T, when condition: @escaping (T, T) -> Bool = { _, _ in true }
    ) -> some View {
        modifier(HapticModifier(haptic: haptic, trigger: trigger, condition: condition))
    }
}

private struct HapticModifier<T: Equatable>: ViewModifier {
    let haptic: Haptic
    let trigger: T
    let condition: (T, T) -> Bool
    @Environment(\.hapticsEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.sensoryFeedback(haptic.feedback, trigger: trigger) { old, new in
            isEnabled && condition(old, new)
        }
    }
}
