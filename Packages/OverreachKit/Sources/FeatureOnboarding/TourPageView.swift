import DesignSystem
import OnboardingPresentation
import SwiftUI

// Views only: the tour's static copy and animation. The page order comes from `OnboardingModel` (ADR-0014).

/// What one tour page says.
struct TourContent {
    let symbol: String
    let title: LocalizedStringKey
    let body: LocalizedStringKey
    let highlights: [(symbol: String, text: LocalizedStringKey)]

    static func `for`(_ page: OnboardingModel.TourPage) -> TourContent {
        switch page {
        case .welcome:
            TourContent(
                symbol: "figure.strengthtraining.traditional", title: "Welcome to Overreach",
                body: "Push smart, recover smarter: a gym log that explains every target.",
                highlights: [
                    ("list.bullet.clipboard.fill", "Log like in Strong, or import your history"),
                    ("chart.line.uptrend.xyaxis", "Targets from your own sessions"),
                    ("lock.shield.fill", "Your data stays on your iPhone"),
                ]
            )
        case .logging:
            TourContent(
                symbol: "dumbbell.fill", title: "Log in seconds",
                body: "Each set starts with today's target. Correct what changed, rate the effort and tap the circle.",
                highlights: [
                    ("flame.fill", "Warm-up sets suggested for you"),
                    ("gauge.with.dots.needle.50percent", "RPE or reps in reserve, your choice"),
                    ("timer.circle.fill", "Rest timer after every set"),
                ]
            )
        case .coaching:
            TourContent(
                symbol: "chart.line.uptrend.xyaxis.circle.fill", title: "Progress you understand",
                body: "The app proposes weight and reps from your history, says why, and how strong the evidence is.",
                highlights: [
                    ("exclamationmark.triangle.fill", "Stalls explained, with what to try"),
                    ("list.bullet.clipboard.fill", "A summary after every session"),
                    ("trophy.fill", "Records and next targets"),
                ]
            )
        case .assistant:
            TourContent(
                symbol: "bubble.left.and.text.bubble.right.fill", title: "Plan with your AI",
                body: "Share your training as data with ChatGPT or Claude, talk it through, and bring routines back.",
                highlights: [
                    ("doc.text.fill", "Raw data, no hidden instructions"),
                    ("eye.fill", "See every change before it is saved"),
                    ("arrow.triangle.2.circlepath", "Corrections the AI understands"),
                ]
            )
        case .safety:
            TourContent(
                symbol: "lock.icloud.fill", title: "Your data, safe",
                body: "Choose an iCloud Drive folder and the app backs up on its own after every session.",
                highlights: [
                    ("icloud.fill", "Automatic backups"),
                    ("arrow.counterclockwise.icloud", "Restore after a reinstall"),
                    ("iphone.gen3", "No account, works offline"),
                ]
            )
        }
    }
}

/// A full-screen tour page: a bouncing symbol, a title and highlights that slide in one after another.
struct TourPageView: View {
    let content: TourContent
    let index: Int
    let count: Int
    let isLast: Bool
    let canGoBack: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipTour: () -> Void
    let onSkipSetup: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.large) {
            HStack {
                if canGoBack {
                    Button("Back", systemImage: "chevron.left", action: onBack)
                        .labelStyle(.iconOnly)
                }
                Spacer()
                Button("Skip setup", action: onSkipSetup)
            }
            ScrollView {
                VStack(spacing: Spacing.large) {
                    Image(systemName: content.symbol)
                        .font(.system(size: 84, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                        .padding(.top, Spacing.large)
                        .accessibilityHidden(true)
                    Text(content.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(content.body)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        ForEach(Array(content.highlights.enumerated()), id: \.offset) { offset, highlight in
                            FeatureHighlightRow(symbol: highlight.symbol, title: Text(highlight.text))
                                .opacity(appeared || reduceMotion ? 1 : 0)
                                .offset(y: appeared || reduceMotion ? 0 : 16)
                                .animation(.spring(duration: 0.5).delay(0.15 * Double(offset + 1)), value: appeared)
                        }
                    }
                    .padding(Spacing.medium)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            PageDots(count: count, index: index)
            HStack {
                if !isLast {
                    Button("Skip tour", action: onSkipTour)
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(action: onNext) {
                    if isLast {
                        Text("Set up")
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(Spacing.medium)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -60 { onNext() }
            if value.translation.width > 60, canGoBack { onBack() }
        })
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.4)) { appeared = true }
        }
    }
}
