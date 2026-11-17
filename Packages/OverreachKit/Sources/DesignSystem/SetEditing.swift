import Domain
import Foundation
import SwiftUI

// Set editing components shared by the live logger (FeatureWorkout) and session editing (FeatureHistory).
// Features cannot import each other, so shared UI lives here. Components take display values only.

/// Weight, reps and RPE fields of one set. The caller adds the set number and trailing controls.
public struct SetValueFields: View {
    @Binding private var weightKg: Double?
    @Binding private var reps: Int?
    @Binding private var rpe: Double?

    /// RPE values offered in the picker.
    public static let rpeValues: [Double] = Array(stride(from: 6.0, through: 10.0, by: 0.5))

    public init(weightKg: Binding<Double?>, reps: Binding<Int?>, rpe: Binding<Double?>) {
        _weightKg = weightKg
        _reps = reps
        _rpe = rpe
    }

    public var body: some View {
        TextField("kg", value: $weightKg, format: .number)
            .numericKeyboard(decimal: true)
            .multilineTextAlignment(.trailing)
        Text("kg").foregroundStyle(.secondary)
        TextField("reps", value: $reps, format: .number)
            .numericKeyboard(decimal: false)
            .multilineTextAlignment(.trailing)
        Text("reps").foregroundStyle(.secondary)
        Picker("RPE", selection: $rpe) {
            Text("RPE –").tag(Double?.none)
            // Keep a value outside the usual range (e.g. imported RPE 5) selectable.
            ForEach(rpeOptions, id: \.self) { value in
                Text("RPE \(value.formatted())").tag(Double?.some(value))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private var rpeOptions: [Double] {
        guard let rpe, !Self.rpeValues.contains(rpe) else { return Self.rpeValues }
        return (Self.rpeValues + [rpe]).sorted()
    }
}

/// The set number shown at the start of a set row.
public struct SetNumberLabel: View {
    private let number: Int

    public init(_ number: Int) {
        self.number = number
    }

    public var body: some View {
        Text("\(number)")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 20)
    }
}

extension TrainingFocus {
    /// User-facing name of the focus.
    public var title: String {
        switch self {
        case .strength: "Strength"
        case .hypertrophy: "Hypertrophy"
        case .mixed: "Mixed"
        case .endurance: "Endurance"
        }
    }
}

extension View {
    /// A numeric keyboard on iOS; nothing elsewhere.
    @ViewBuilder
    public func numericKeyboard(decimal: Bool) -> some View {
        #if os(iOS)
        keyboardType(decimal ? .decimalPad : .numberPad)
        #else
        self
        #endif
    }
}

/// An item of `ExercisePicker`: what to show and the names search should match.
public struct PickerItem: Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let searchTerms: [String]

    public init(id: UUID, title: String, searchTerms: [String]) {
        self.id = id
        self.title = title
        self.searchTerms = searchTerms
    }
}

/// Searchable list of items (exercises), presented as a sheet.
public struct ExercisePicker: View {
    private let title: LocalizedStringKey
    private let items: [PickerItem]
    private let onPick: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    public init(title: LocalizedStringKey = "Add exercise", items: [PickerItem], onPick: @escaping (UUID) -> Void) {
        self.title = title
        self.items = items
        self.onPick = onPick
    }

    private var filtered: [PickerItem] {
        guard !query.isEmpty else { return items }
        return items.filter { item in item.searchTerms.contains { $0.localizedStandardContains(query) } }
    }

    public var body: some View {
        NavigationStack {
            List(filtered) { item in
                Button(item.title) {
                    onPick(item.id)
                    dismiss()
                }
            }
            .searchable(text: $query)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
