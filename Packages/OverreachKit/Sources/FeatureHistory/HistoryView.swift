import DesignSystem
import SwiftUI

/// Calendar of strength sessions and runs, with session detail (phase 1).
public struct HistoryView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "History", systemImage: "calendar", phase: 1)
    }
}

#Preview {
    HistoryView()
}
