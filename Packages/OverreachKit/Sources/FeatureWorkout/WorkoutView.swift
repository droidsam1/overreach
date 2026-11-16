import DesignSystem
import SwiftUI

/// Routines and the live session logger (phase 1).
public struct WorkoutView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "Train", systemImage: "dumbbell", phase: 1)
    }
}

#Preview {
    WorkoutView()
}
