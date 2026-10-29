import SwiftData
import SwiftUI

/// Edit a logged food: amount, meal, time, name and macros; swap it for another food, log it again or delete it.
struct EditFoodLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let log: FoodLog
    /// The fields as shown. Numbers stay text while typing; fields left as they were save exactly as logged.
    @State private var draft: Draft
    /// The fields when the sheet opened, so Save only writes (and syncs) what changed.
    @State private var original: Draft
    @State private var replacing = false
    @State private var confirmingDelete = false

    init(log: FoodLog) {
        self.log = log
        let draft = Draft(log)
        _draft = State(initialValue: draft)
        _original = State(initialValue: draft)
    }

    private struct Draft: Equatable {
        var name: String
        var place: String
        var serving: String
        var source: String
        var meal: Meal
        var eatenAt: Date
        var servings: String
        var kcal: String
        var protein: String
        var carbs: String
        var fat: String

        init(_ log: FoodLog) {
            name = log.name
            place = log.place ?? ""
            serving = log.serving ?? ""
            source = log.source
            meal = Meal(rawValue: log.meal) ?? .snack
            eatenAt = log.eatenAt
            servings = Self.text(log.servings, digits: 2)
            kcal = Self.text(log.kcal)
            protein = Self.text(log.protein)
            carbs = Self.text(log.carbs)
            fat = Self.text(log.fat)
        }

        static func text(_ value: Double, digits: Int = 1) -> String {
            value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
        }
    }

    /// What Save and Log again write.
    private struct Entry {
        var name: String
        var place: String?
        var serving: String?
        var source: String
        var meal: String
        var eatenAt: Date
        var servings: Double
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    /// A typed amount rounded to what the server keeps (servings to 0.01, macros to 0.1); empty is 0, nil if it isn't
    /// a number ≥ 0.
    private static func parse(_ text: String, digits: Int = 1) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty { return 0 }
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        let scale = digits == 2 ? 100.0 : 10.0
        return (value * scale).rounded() / scale
    }

    /// The logged value while a field is as it was, else `edited` of what's in it.
    private func kept<T: Equatable, V>(_ key: KeyPath<Draft, T>, _ logged: V, _ edited: (T) -> V) -> V {
        draft[keyPath: key] == original[keyPath: key] ? logged : edited(draft[keyPath: key])
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(200))
    }

    private func amount(_ key: KeyPath<Draft, String>, _ logged: Double) -> Double? {
        kept(key, logged as Double?) { Self.parse($0) }
    }

    private var typedServings: Double? {
        kept(\.servings, log.servings as Double?) { Self.parse($0, digits: 2) }.flatMap { $0 > 0 && $0 <= 50 ? $0 : nil }
    }

    /// Nil while a field is invalid: no name, servings not above 0 (or over 50), or a macro that isn't a number.
    private var entry: Entry? {
        guard let name = kept(\.name, log.name as String?, trimmed), let servings = typedServings,
              let kcal = amount(\.kcal, log.kcal), let protein = amount(\.protein, log.protein),
              let carbs = amount(\.carbs, log.carbs), let fat = amount(\.fat, log.fat),
              [kcal, protein, carbs, fat].allSatisfy({ $0 < 100_000 }) else { return nil }
        return Entry(
            name: name, place: kept(\.place, log.place, trimmed), serving: kept(\.serving, log.serving, trimmed),
            source: kept(\.source, log.source) { $0 }, meal: kept(\.meal, log.meal) { $0.rawValue },
            eatenAt: kept(\.eatenAt, log.eatenAt) { $0 },
            servings: servings, kcal: kcal, protein: protein, carbs: carbs, fat: fat
        )
    }

    /// Any time today is fine (a meal you're about to eat); later days wouldn't show anywhere yet.
    private var latest: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        return tomorrow.addingTimeInterval(-60)
    }

    var body: some View {
        let entry = entry
        let servings = typedServings ?? 0
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    TextField("Where (optional)", text: $draft.place)
                    TextField("Serving (e.g. 1 bar, 40 g)", text: $draft.serving)
                    Button { replacing = true } label: { Label("Replace food…", systemImage: "arrow.triangle.2.circlepath") }
                }
                Section {
                    LabeledContent("Servings") {
                        HStack {
                            TextField("Servings", text: $draft.servings)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 90)
                            Stepper("Servings", onIncrement: servings < 50 ? { step(1) } : nil,
                                    onDecrement: servings > 0.5 ? { step(-1) } : nil)
                                .labelsHidden()
                        }
                    }
                    Picker("Meal", selection: $draft.meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Eaten", selection: $draft.eatenAt, in: ...latest)
                } footer: {
                    if servings == 0 { Text("Servings must be more than 0 and at most 50.") }
                }
                Section("Per serving") {
                    field("Calories", \.kcal)
                    field("Protein (g)", \.protein)
                    field("Carbs (g)", \.carbs)
                    field("Fat (g)", \.fat)
                }
                Section("Total") {
                    LabeledContent("Calories", value: "\(Int(((amount(\.kcal, log.kcal) ?? 0) * servings).rounded()))")
                    LabeledContent("Protein", value: "\(Format.number((amount(\.protein, log.protein) ?? 0) * servings)) g")
                    LabeledContent("Carbs", value: "\(Format.number((amount(\.carbs, log.carbs) ?? 0) * servings)) g")
                    LabeledContent("Fat", value: "\(Format.number((amount(\.fat, log.fat) ?? 0) * servings)) g")
                }
                Section {
                    Button { logAgain() } label: { Label("Log again now", systemImage: "plus.circle") }
                        .disabled(entry == nil)
                    Button("Delete food", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete this food?", isPresented: $confirmingDelete) {
                            Button("Delete", role: .destructive) {
                                log.softDelete()
                                dismiss()
                            }
                        }
                } footer: {
                    Text("Log again adds what's shown as a new \(Meal.current().label.lowercased()) entry for now; this one stays as it was.")
                }
            }
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(entry == nil) }
            }
            .sheet(isPresented: $replacing) {
                NavigationStack {
                    List {
                        Section {
                            AddFoodLinks()
                        } footer: {
                            Text("Keeps the servings, meal and time.")
                        }
                    }
                    .navigationTitle("Replace food")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { replacing = false } }
                    }
                }
                .environment(\.foodPick, replace)
            }
        }
        .interactiveDismissDisabled(draft != original)
    }

    private func field(_ label: String, _ key: WritableKeyPath<Draft, String>) -> some View {
        LabeledContent(label) {
            TextField("0", text: $draft[dynamicMember: key])
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Steps to the next half serving, so 1.3 goes to 1.5 or 1.
    private func step(_ direction: Double) {
        let halves = (typedServings ?? 1) * 2
        let next = direction > 0 ? (halves + 1e-9).rounded(.down) + 1 : (halves - 1e-9).rounded(.up) - 1
        draft.servings = Draft.text(min(50, max(0.5, next / 2)), digits: 2)
    }

    /// Swaps in a food from the pickers, keeping the servings, meal and time.
    private func replace(_ item: FoodItem, source: String, place: String?) {
        draft.name = item.name
        draft.serving = item.serving
        draft.source = source
        draft.place = place ?? ""
        draft.kcal = Draft.text(item.kcal)
        draft.protein = Draft.text(item.protein)
        draft.carbs = Draft.text(item.carbs)
        draft.fat = Draft.text(item.fat)
        replacing = false
    }

    private func save() {
        guard let entry else { return }
        var changed = false
        func set<T: Equatable>(_ key: ReferenceWritableKeyPath<FoodLog, T>, _ value: T) {
            guard log[keyPath: key] != value else { return }
            log[keyPath: key] = value
            changed = true
        }
        set(\.name, entry.name)
        set(\.place, entry.place)
        set(\.serving, entry.serving)
        set(\.source, entry.source)
        set(\.meal, entry.meal)
        set(\.eatenAt, entry.eatenAt)
        set(\.servings, entry.servings)
        set(\.kcal, entry.kcal)
        set(\.protein, entry.protein)
        set(\.carbs, entry.carbs)
        set(\.fat, entry.fat)
        if changed { log.touch() }
        dismiss()
    }

    private func logAgain() {
        guard let entry else { return }
        context.insert(FoodLog(
            meal: Meal.current().rawValue, source: entry.source, place: entry.place, name: entry.name, serving: entry.serving,
            servings: entry.servings, kcal: entry.kcal, protein: entry.protein, carbs: entry.carbs, fat: entry.fat
        ))
        try? context.save()
        dismiss()
    }
}
