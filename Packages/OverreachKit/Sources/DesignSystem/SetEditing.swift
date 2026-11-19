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
    public static let rpeValues: [Double] = RPEScale.values.reversed()

    public init(weightKg: Binding<Double?>, reps: Binding<Int?>, rpe: Binding<Double?>) {
        _weightKg = weightKg
        _reps = reps
        _rpe = rpe
    }

    public var body: some View {
        NumberField(placeholder: "kg", unit: "kg", accessibilityLabel: "Weight in kilograms", allowsDecimals: true,
                    value: $weightKg)
        NumberField(placeholder: "reps", unit: "reps", accessibilityLabel: "Repetitions", allowsDecimals: false,
                    value: Binding(
                        get: { reps.map(Double.init) },
                        set: { reps = $0.map { Int($0) } }
                    ))
        Menu {
            Picker("RPE", selection: $rpe) {
                Text("No RPE").tag(Double?.none)
                // Keep a value outside the usual range (e.g. imported RPE 5) selectable.
                ForEach(rpeOptions, id: \.self) { value in
                    RPEText(value: value).tag(Double?.some(value))
                }
            }
        } label: {
            Group {
                if let rpe {
                    Text("RPE \(rpe.formatted())")
                } else {
                    Text("RPE –")
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .accessibilityLabel("Effort (RPE)")
    }

    private var rpeOptions: [Double] {
        guard let rpe, !Self.rpeValues.contains(rpe) else { return Self.rpeValues }
        return (Self.rpeValues + [rpe]).sorted()
    }
}

/// The set number shown at the start of a set row.
public struct SetNumberLabel: View {
    private let number: Int
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 20

    public init(_ number: Int) {
        self.number = number
    }

    public var body: some View {
        Text("\(number)")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: width)
            .accessibilityLabel("Set \(number)")
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
            .overlay {
                if filtered.isEmpty {
                    ListEmptyState(query: query, title: "No exercises", systemImage: "dumbbell")
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

/// "RPE 8 · 2 reps left": an RPE value with the reps in reserve it stands for (RIR-based RPE scale).
struct RPEText: View {
    let value: Double

    var body: some View {
        if let meaning = RPEScale.meaning(of: value) {
            Text("RPE \(value.formatted())") + Text(verbatim: " · ") + Text(meaning)
        } else {
            Text("RPE \(value.formatted())")
        }
    }
}

/// What each RPE value means, counted as reps left before failure.
enum RPEScale {
    /// From hardest to easiest.
    static let values: [Double] = Array(stride(from: 10.0, through: 6.0, by: -0.5))

    static func meaning(of value: Double) -> LocalizedStringKey? {
        switch value {
        case 10: "0 reps left"
        case 9.5: "maybe 1 rep left"
        case 9: "1 rep left"
        case 8.5: "1–2 reps left"
        case 8: "2 reps left"
        case 7.5: "2–3 reps left"
        case 7: "3 reps left"
        case 6.5: "3–4 reps left"
        case 6: "4+ reps left"
        default: nil
        }
    }
}

/// How to log a set: what to change after lifting, the RPE scale and what notes are for. Static help.
public struct SetLoggingGuide: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        """
                        Each set starts with today's target. After lifting, correct the weight or reps if you did \
                        something different.
                        """,
                        systemImage: "pencil"
                    )
                    Label(
                        "Choose the RPE: how hard the set was, counted as the reps you had left.",
                        systemImage: "gauge.with.dots.needle.50percent"
                    )
                    Label(
                        """
                        Tap the circle when the set is done. Only sets marked as done are saved, and the rest timer \
                        starts.
                        """,
                        systemImage: "checkmark.circle"
                    )
                }
                Section {
                    ForEach(RPEScale.values, id: \.self) { value in
                        HStack {
                            Text("RPE \(value.formatted())").monospacedDigit()
                            Spacer()
                            if let meaning = RPEScale.meaning(of: value) {
                                Text(meaning).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("RPE scale")
                } footer: {
                    Text(
                        """
                        Not sure? Leave it empty and the app only uses weight and reps. If sets at the top of the \
                        range feel harder than the target RPE, the weight waits until they feel easier.
                        """
                    )
                }
                Section {
                    Text(
                        """
                        Use notes for what the numbers miss: pain, technique, sleep or machine settings. They are \
                        saved with the session and included in backups.
                        """
                    )
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("How to log sets")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
