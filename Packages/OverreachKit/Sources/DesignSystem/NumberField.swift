import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A number field for set values (weight, reps), made for quick edits mid-workout:
/// - the whole field, unit included, is the tap target, at least 44 pt high;
/// - focusing it selects the current value, so typing replaces it;
/// - the value updates on every keystroke, so tapping "done" right after typing keeps it (number pads have no
///   return key to commit a formatted field).
struct NumberField: View {
    let placeholder: LocalizedStringKey
    let unit: LocalizedStringKey
    let accessibilityLabel: LocalizedStringKey
    let allowsDecimals: Bool
    @Binding var value: Double?

    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 52
    @State private var text = ""
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            TextField(placeholder, text: input, selection: $selection)
                .focused($isFocused)
                .numericKeyboard(decimal: allowsDecimals)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: valueWidth, idealWidth: valueWidth)
                .accessibilityLabel(accessibilityLabel)
            Text(unit).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear { text = NumberText.text(for: value) }
        .onChange(of: value) {
            if !isFocused { text = NumberText.text(for: value) }
        }
        .onChange(of: isFocused) {
            if isFocused {
                selectAll()
            } else {
                text = NumberText.text(for: value)
            }
        }
    }

    /// Only typed edits write back. Formatting an existing value may round it for display.
    private var input: Binding<String> {
        Binding(get: { text }, set: { newText in
            text = newText
            let parsed = NumberText.value(of: newText, allowsDecimals: allowsDecimals)
            if parsed != value { value = parsed }
        })
    }

    /// Selects the value after the tap has placed the cursor, so the next key replaces it.
    private func selectAll() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard isFocused, !text.isEmpty else { return }
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }
}

/// Text ↔ number for `NumberField`: either decimal separator is accepted while typing.
enum NumberText {
    static func value(of text: String, allowsDecimals: Bool) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }
        if allowsDecimals {
            guard let number = Double(trimmed), number >= 0, number.isFinite else { return nil }
            return number
        }
        guard let number = Int(trimmed), number >= 0 else { return nil }
        return Double(number)
    }

    static func text(for value: Double?, locale: Locale = .current) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }
}

extension View {
    /// A "Done" button above the keyboard and dismissal by scrolling, for screens with number fields.
    public func keyboardDoneButton() -> some View {
        #if canImport(UIKit)
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
                }
            }
        #else
        self
        #endif
    }
}
