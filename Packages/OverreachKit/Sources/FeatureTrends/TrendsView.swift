import DesignSystem
import SwiftUI

/// 30/90-day charts: HRV with its normal band, resting HR, sleep, weekly volume and kilometres (phase 3).
public struct TrendsView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "Trends", systemImage: "chart.xyaxis.line", phase: 3)
    }
}

#Preview {
    TrendsView()
}
