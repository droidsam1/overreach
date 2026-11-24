import Foundation
import SwiftUI

// Set editing components shared by the live logger (FeatureWorkout) and session editing (FeatureHistory).
// Features cannot import each other, so shared UI lives here. Components take display values only.

/// Weight, reps and RPE fields of one set. The caller adds the set number and trailing controls.
public struct SetValueFields: View {
    private let weightUnit: LocalizedStringKey
    private let weightAccessibilityLabel: LocalizedStringKey
    @Binding private var weight: Double?
    @Binding private var reps: Int?
    @Binding private var rpe: Double?
    private let showsRepsInReserve: Bool

    /// RPE values offered in the picker.
    public static let rpeValues: [Double] = RPEScale.values.reversed()

    /// - Parameter showsRepsInReserve: show effort as reps in reserve (RIR = 10 − RPE); the binding stays RPE.
    public init(
        weight: Binding<Double?>, reps: Binding<Int?>, rpe: Binding<Double?>, showsRepsInReserve: Bool = false,
        weightUnit: LocalizedStringKey = "kg", weightAccessibilityLabel: LocalizedStringKey = "Weight in kilograms"
    ) {
        self.weightUnit = weightUnit
        self.weightAccessibilityLabel = weightAccessibilityLabel
        _weight = weight
        _reps = reps
        _rpe = rpe
        self.showsRepsInReserve = showsRepsInReserve
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.small) { fields }
            VStack(alignment: .leading, spacing: Spacing.xSmall) { fields }
        }
    }

    @ViewBuilder private var fields: some View {
        NumberField(placeholder: weightUnit, unit: weightUnit, accessibilityLabel: weightAccessibilityLabel,
                    allowsDecimals: true, value: $weight)
        NumberField(placeholder: "reps", unit: "reps", accessibilityLabel: "Repetitions", allowsDecimals: false,
                    value: Binding(
                        get: { reps.map(Double.init) },
                        set: { reps = $0.map { Int($0) } }
                    ))
        Menu {
            Picker(selection: $rpe) {
                (showsRepsInReserve ? Text("No RIR") : Text("No RPE")).tag(Double?.none)
                // Keep a value outside the usual range (e.g. imported RPE 5) selectable.
                ForEach(rpeOptions, id: \.self) { value in
                    RPEText(value: value, asRepsInReserve: showsRepsInReserve).tag(Double?.some(value))
                }
            } label: {
                showsRepsInReserve ? Text("RIR") : Text("RPE")
            }
        } label: {
            effortValue
                .padding(.horizontal, Spacing.small)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(showsRepsInReserve ? Text("Reps in reserve (RIR)") : Text("Effort (RPE)"))
        .accessibilityValue(effortValue)
    }

    private var effortValue: Text {
        if let rpe {
            return showsRepsInReserve
                ? Text("RIR \(RPEScale.repsInReserve(rpe).formatted())")
                : Text("RPE \(rpe.formatted())")
        }
        return showsRepsInReserve ? Text("RIR –") : Text("RPE –")
    }

    private var rpeOptions: [Double] {
        guard let rpe, !Self.rpeValues.contains(rpe) else { return Self.rpeValues }
        return (Self.rpeValues + [rpe]).sorted()
    }
}

/// The set number shown at the start of a set row; "W" for warm-up sets.
public struct SetNumberLabel: View {
    private let number: Int
    private let isWarmUp: Bool
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 20

    public init(_ number: Int, isWarmUp: Bool = false) {
        self.number = number
        self.isWarmUp = isWarmUp
    }

    public var body: some View {
        Group {
            if isWarmUp {
                Text("W")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Warm-up set \(number)")
            } else {
                Text("\(number)")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Set \(number)")
            }
        }
        .font(.subheadline.monospacedDigit())
        .frame(minWidth: width)
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
///
/// With `createForm`, an exercise search does not find can be created on the spot: a "Create “…”" row follows the
/// results and a + button opens an empty form. The form is pushed with the typed text as its name and calls the
/// `finish` it receives once the exercise was created and added, which closes the picker.
public struct ExercisePicker<CreateForm: View>: View {
    private let title: LocalizedStringKey
    private let items: [PickerItem]
    private let onPick: (UUID) -> Void
    private let createForm: ((_ name: String, _ finish: @escaping () -> Void) -> CreateForm)?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var newExercise: NewExerciseRequest?

    public init(
        title: LocalizedStringKey = "Add exercise",
        items: [PickerItem],
        onPick: @escaping (UUID) -> Void,
        @ViewBuilder createForm: @escaping (_ name: String, _ finish: @escaping () -> Void) -> CreateForm
    ) {
        self.title = title
        self.items = items
        self.onPick = onPick
        self.createForm = createForm
    }

    private var filtered: [PickerItem] {
        guard !query.isEmpty else { return items }
        return items.filter { item in item.searchTerms.contains { $0.localizedStandardContains(query) } }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { item in
                        Button(item.title) {
                            onPick(item.id)
                            dismiss()
                        }
                    }
                }
                if createForm != nil, !trimmedQuery.isEmpty {
                    Section {
                        Button {
                            newExercise = NewExerciseRequest(name: trimmedQuery)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                    Text("Create exercise")
                                    Text(verbatim: "“\(trimmedQuery)”")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                    } header: {
                        if filtered.isEmpty { Text("No matches") }
                    } footer: {
                        Text("Not in the list? Create it and choose its muscles so its volume counts.")
                    }
                }
            }
            .overlay {
                if filtered.isEmpty && (createForm == nil || trimmedQuery.isEmpty) {
                    ListEmptyState(query: query, title: "No exercises", systemImage: "dumbbell")
                }
            }
            .searchable(text: $query)
            .navigationTitle(title)
            .navigationDestination(item: $newExercise) { request in
                createForm?(request.name) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if createForm != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New exercise", systemImage: "plus") {
                            newExercise = NewExerciseRequest(name: trimmedQuery)
                        }
                    }
                }
            }
        }
    }
}

extension ExercisePicker where CreateForm == EmptyView {
    /// A picker that only offers `items`.
    public init(title: LocalizedStringKey = "Add exercise", items: [PickerItem], onPick: @escaping (UUID) -> Void) {
        self.title = title
        self.items = items
        self.onPick = onPick
        createForm = nil
    }
}

/// One push of the create form; a new id each time, so the form starts from the current search text.
private struct NewExerciseRequest: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

/// "RPE 8 · 2 reps left" (or "RIR 2 · 2 reps left"): an RPE value with the reps in reserve it stands for.
struct RPEText: View {
    let value: Double
    var asRepsInReserve = false

    var body: some View {
        if let meaning = RPEScale.meaning(of: value) {
            name + Text(verbatim: " · ") + Text(meaning)
        } else {
            name
        }
    }

    private var name: Text {
        asRepsInReserve
            ? Text("RIR \(RPEScale.repsInReserve(value).formatted())")
            : Text("RPE \(value.formatted())")
    }
}

/// What each RPE value means, counted as reps left before failure.
enum RPEScale {
    /// From hardest to easiest.
    static let values: [Double] = Array(stride(from: 10.0, through: 6.0, by: -0.5))

    static func repsInReserve(_ rpe: Double) -> Double { max(0, 10 - rpe) }

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

/// How to log a set: what to change after lifting, how to rate effort (`rir-estimation`, `rir-calibration`),
/// the scale and what notes are for. With a binding, it also chooses between RPE and reps in reserve.
public struct SetLoggingGuide: View {
    @Environment(\.dismiss) private var dismiss
    private let showsRepsInReserve: Binding<Bool>?

    public init(showsRepsInReserve: Binding<Bool>? = nil) {
        self.showsRepsInReserve = showsRepsInReserve
    }

    public var body: some View {
        NavigationStack {
            List {
                if let showsRepsInReserve {
                    Section {
                        Picker("Log effort as", selection: showsRepsInReserve) {
                            Text("RPE").tag(false)
                            Text("Reps in reserve (RIR)").tag(true)
                        }
                    } footer: {
                        Text("Both mean the same: RPE = 10 − reps in reserve. Your history and targets do not change.")
                    }
                }
                Section {
                    Label(
                        """
                        Each set starts with today's target. After lifting, correct the weight or reps if you did \
                        something different.
                        """,
                        systemImage: "pencil"
                    )
                    Label(
                        "Choose the effort: how many reps you had left, as RPE or reps in reserve.",
                        systemImage: "gauge.with.dots.needle.50percent"
                    )
                    Label(
                        """
                        Tap the circle when the set is done. Only sets marked as done are saved, and the rest timer \
                        starts.
                        """,
                        systemImage: "checkmark.circle"
                    )
                    Label(
                        """
                        Sets marked W are suggested warm-ups. Mark the ones you do; they are saved apart and do not \
                        count for progress. Swipe to delete the ones you skip.
                        """,
                        systemImage: "flame"
                    )
                }
                Section {
                    Text(
                        """
                        When the set ends, ask yourself: how many more reps could I have done with good form? That \
                        number is your reps in reserve.
                        """
                    )
                    Text(
                        """
                        0: you could not have done another. 1: the last rep was a real fight and clearly slowed down. \
                        2–3: hard, but you had some left. 4 or more: comfortable.
                        """
                    )
                    Text(
                        """
                        Most people guess about 1 rep too few, more so in long sets and with light loads. If you \
                        hesitate between two values, pick the one with more reps left. (moderate evidence)
                        """
                    )
                    Text(
                        """
                        To check yourself, now and then take the last set of a safe exercise, such as a machine or \
                        an isolation exercise, to failure and compare. Never with heavy barbell lifts without \
                        safeties. (coaching heuristic)
                        """
                    )
                } header: {
                    Text("How to rate effort")
                }
                Section {
                    ForEach(RPEScale.values, id: \.self) { value in
                        HStack {
                            Text("RPE \(value.formatted())").monospacedDigit()
                            Text(verbatim: "·").foregroundStyle(.secondary)
                            Text("RIR \(RPEScale.repsInReserve(value).formatted())").monospacedDigit()
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

#Preview("Set editor at an accessibility text size") {
    List {
        SetEntryRow(number: SetNumberLabel(1)) {
            SetValueFields(weight: .constant(102.5), reps: .constant(12), rpe: .constant(8))
        } action: {
            Image(systemName: "checkmark.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
