import DesignSystem
import OnboardingPresentation
import SwiftUI

// Views only: layout and animation. The highlights come from `WhatsNewModel` (ADR-0014).

/// "What's new" after an update.
public struct WhatsNewView: View {
    private let model: WhatsNewModel
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 72

    public init(model: WhatsNewModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            AnimatedBackdrop()
            VStack(spacing: Spacing.large) {
                ScrollView {
                    VStack(spacing: Spacing.large) {
                        Image(systemName: "sparkles")
                            .font(.system(size: heroSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                            .symbolEffect(.bounce, options: .nonRepeating, value: appeared && !reduceMotion)
                            .padding(.top, Spacing.large)
                            .accessibilityHidden(true)
                        Text(model.title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        VStack(alignment: .leading, spacing: Spacing.medium) {
                            ForEach(Array(model.highlights.enumerated()), id: \.element.id) { offset, highlight in
                                FeatureHighlightRow(
                                    symbol: highlight.symbol, title: Text(highlight.title), detail: Text(highlight.detail)
                                )
                                .opacity(appeared || reduceMotion ? 1 : 0)
                                .offset(y: appeared || reduceMotion ? 0 : 16)
                                .animation(.spring(duration: 0.5).delay(0.08 * Double(offset + 1)), value: appeared)
                            }
                        }
                        .padding(Spacing.medium)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(Spacing.medium)
                }
                Button {
                    Task { await model.dismiss() }
                } label: {
                    Text("Continue")
                }
                .buttonStyle(BrandButtonStyle())
                .padding(Spacing.medium)
            }
        }
        .onAppear { appeared = true }
    }
}
