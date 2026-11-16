import DesignSystem
import SwiftUI

/// Exercise catalog with progress, estimated 1RM, progression scheme, PRs and stalls (phases 1 and 3).
public struct ExercisesView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "Exercises", systemImage: "figure.strengthtraining.traditional", phase: 1)
    }
}

#Preview {
    ExercisesView()
}
