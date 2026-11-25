import SwiftUI

/// A status message shown alongside whatever content is still available.
public struct InlineNotice: View {
    private let message: Text
    private let tone: StatusTone
    private let retry: (() -> Void)?

    public init(_ message: Text, tone: StatusTone, retry: (() -> Void)? = nil) {
        self.message = message
        self.tone = tone
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    status.font(.subheadline.weight(.semibold)).foregroundStyle(tone.accent)
                    message.font(.subheadline).foregroundStyle(.primary)
                }
            } icon: {
                Image(systemName: tone.symbolName)
                    .foregroundStyle(tone.accent)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            if let retry {
                Button(action: retry) {
                    Text("Try again")
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var status: Text {
        switch tone {
        case .positive: Text("Success")
        case .caution: Text("Warning")
        case .critical: Text("Error")
        case .neutral: Text("Note")
        case .done: Text("Done")
        }
    }
}

/// Indeterminate progress with an optional explanation of what is loading.
public struct LoadingState: View {
    private let title: LocalizedStringKey?

    public init(_ title: LocalizedStringKey? = nil) {
        self.title = title
    }

    public var body: some View {
        Group {
            if let title {
                ProgressView(title).multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
    }
}
