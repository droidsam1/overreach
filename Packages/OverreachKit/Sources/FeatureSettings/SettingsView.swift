import DesignSystem
import SwiftUI

/// Connections (Health, Garmin), Strong import, readiness thresholds, report template, backup,
/// and in phase 4 the AI provider, model and API key.
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "Settings", systemImage: "gearshape", phase: 1)
    }
}

#Preview {
    SettingsView()
}
