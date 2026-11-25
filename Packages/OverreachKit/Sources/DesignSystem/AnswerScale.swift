import SwiftUI

/// One option of an `AnswerScale`: an SF Symbol and a short word.
public struct AnswerOption: Identifiable, Sendable, Equatable {
    public let id: String
    public let symbolName: String
    public let label: String

    public init(id: String, symbolName: String, label: String) {
        self.id = id
        self.symbolName = symbolName
        self.label = label
    }
}

/// A row of 3–5 large options answered with one tap. The picked one shows a checkmark and plays a haptic.
/// At accessibility text sizes it wraps to two rows. Display values only: the caller owns the meaning of an id.
public struct AnswerScale: View {
    private let options: [AnswerOption]
    private let selectedID: String?
    private let onSelect: (String) -> Void
    private let tone: StatusTone

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        options: [AnswerOption], selectedID: String?, tone: StatusTone = .positive,
        onSelect: @escaping (String) -> Void
    ) {
        self.options = options
        self.selectedID = selectedID
        self.tone = tone
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: Spacing.small) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Spacing.small) {
                    ForEach(row) { option in
                        button(option)
                    }
                }
            }
        }
        .haptic(.selected, trigger: selectedID) { _, new in new != nil }
        .accessibilityElement(children: .contain)
    }

    private var rows: [[AnswerOption]] {
        guard typeSize.isAccessibilitySize, options.count > 2 else { return [options] }
        let perRow = (options.count + 1) / 2
        return stride(from: 0, to: options.count, by: perRow).map {
            Array(options[$0..<min($0 + perRow, options.count)])
        }
    }

    private func button(_ option: AnswerOption) -> some View {
        let isSelected = option.id == selectedID
        return Button {
            onSelect(option.id)
        } label: {
            VStack(spacing: Spacing.xSmall) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : option.symbolName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? tone.accent : Color.primary)
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, Spacing.small)
            .background(
                isSelected ? tone.surface : Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.tile)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tile)
                    .strokeBorder(isSelected ? tone.accent : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: Radius.tile))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Answer scale, light") {
    AnswerScale(options: previewOptions, selectedID: "4") { _ in }
        .padding().preferredColorScheme(.light)
}

#Preview("Answer scale, dark") {
    AnswerScale(options: previewOptions, selectedID: nil) { _ in }
        .padding().preferredColorScheme(.dark)
}

#Preview("Accessibility size") {
    AnswerScale(options: previewOptions, selectedID: "2") { _ in }
        .padding().environment(\.dynamicTypeSize, .accessibility3)
}

private let previewOptions = [
    AnswerOption(id: "1", symbolName: "cloud.bolt", label: "Awful"),
    AnswerOption(id: "2", symbolName: "cloud.rain", label: "Low"),
    AnswerOption(id: "3", symbolName: "minus.circle", label: "Okay"),
    AnswerOption(id: "4", symbolName: "sun.min", label: "Good"),
    AnswerOption(id: "5", symbolName: "sun.max", label: "Great"),
]
