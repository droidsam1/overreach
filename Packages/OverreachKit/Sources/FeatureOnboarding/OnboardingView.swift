import DesignSystem
import SwiftUI

/// Guided setup: profile (age, sex, max HR and zones), Health permissions, optional Garmin sign-in,
/// optional Strong import, and training plan. Every step can be skipped (phase 2).
public struct OnboardingView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "Welcome", systemImage: "hand.wave", phase: 2)
    }
}

#Preview {
    OnboardingView()
}
