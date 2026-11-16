import DesignSystem
import SwiftUI

/// Running and strength goals, weekly routine, available days and deload weeks (phase 3).
public struct PlanView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "Plan", systemImage: "list.bullet.clipboard", phase: 3)
    }
}

#Preview {
    PlanView()
}
