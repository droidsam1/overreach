import DesignSystem
import SwiftUI

/// Prototype: share the Markdown report with ChatGPT/Claude (phase 3).
/// Later: in-app chat through an `LLMProvider` (phase 4, ADR-0006).
public struct AssistantView: View {
    public init() {}

    public var body: some View {
        ComingSoonView(title: "Assistant", systemImage: "bubble.left.and.text.bubble.right", phase: 3)
    }
}

#Preview {
    AssistantView()
}
