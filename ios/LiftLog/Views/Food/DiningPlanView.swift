import LiftKit
import SwiftData
import SwiftUI

/// "What to eat": the best plate at each dining hall for one meal, ranked, from today's live menus and what's left of
/// today's targets (DiningPlanner).
struct DiningPlanView: View {
    @Query(filter: #Predicate<FoodLog> { $0.deletedAt == nil }, sort: \FoodLog.eatenAt, order: .reverse) private var logs: [FoodLog]
    @Query(sort: \BodyMetric.measuredAt, order: .reverse) private var metrics: [BodyMetric]
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @AppStorage(Prefs.sex) private var sexRaw = ""
    @Environment(HealthService.self) private var health
    @State private var meal = Meal.current().rawValue
    @State private var target: DiningPlanner.Target?
    /// Today's calories and protein left when the target was set, for the line under it; nil without daily targets.
    @State private var left: DiningPlanner.Macros?
    /// The halls for `results.meal`, best plate first; nil until the first load.
    @State private var results: (meal: String, halls: [HallPlan])?
    @State private var picked: HallPlate?
    /// Halls whose plate was logged since the meal was picked.
    @State private var logged: Set<String> = []

    /// One hall's outcome for the meal.
    struct HallPlan: Identifiable {
        let hall: DiningHall
        var plate: DiningPlanner.Plate?
        /// The hall posted a menu for this meal today.
        var posted = false
        var failed = false
        var id: String { hall.id }
    }

    struct HallPlate: Identifiable {
        let hall: DiningHall
        let plate: DiningPlanner.Plate
        var id: String { hall.id }
    }

    /// Every hall's meals, in order: breakfast, lunch, dinner, overnight.
    private static let meals: [String] = {
        var seen = Set<String>()
        return DiningService.halls.flatMap(\.meals).filter { seen.insert($0).inserted }
    }()

    var body: some View {
        List {
            Picker("Meal", selection: $meal) {
                ForEach(Self.meals, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            if let results, results.meal == meal {
                if results.halls.allSatisfy(\.failed) {
                    Section {
                        Text("Couldn't load today's menus. Check your connection and try again.").foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }
                    }
                } else if !results.halls.contains(where: \.posted) {
                    Section {
                        Text("No dining hall has posted today's \(meal) menu.").foregroundStyle(.secondary)
                        ForEach(results.halls) { plan in
                            NavigationLink(plan.hall.name) { HallMenuView(hall: plan.hall) }
                        }
                    } footer: {
                        Text("Menus can be empty on weekends and breaks. The full menus still list the always-available staples.")
                    }
                } else {
                    if let target { targetSection(target) }
                    ForEach(results.halls) { plan in
                        hallSection(plan, best: plan.id == results.halls.first?.id, last: plan.id == results.halls.last?.id)
                    }
                }
            } else {
                if let target { targetSection(target) }
                ProgressView("Loading today's menus").frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("What to eat")
        .task(id: meal) {
            logged = []
            await load()
        }
        .refreshable { await load() }
        .sheet(item: $picked) { choice in
            LogPlateSheet(hall: choice.hall, plate: choice.plate, meal: Meal(rawValue: meal) ?? .snack) { logged.insert(choice.hall.id) }
        }
    }

    private func targetSection(_ target: DiningPlanner.Target) -> some View {
        Section {
            VStack(spacing: 8) {
                HStack {
                    stat(target.protein, "g protein")
                    stat(target.kcal, "kcal")
                    stat(target.carbs, "carbs")
                    stat(target.fat, "fat")
                }
                Text(note(target))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("This meal")
        }
    }

    private func stat(_ value: Double, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(Int(value).formatted()).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// One line on where the target comes from.
    private func note(_ target: DiningPlanner.Target) -> String {
        if target.estimated {
            return metrics.contains(where: { $0.deletedAt == nil && $0.bodyWeight != nil })
                ? "No daily targets yet, so this is 0.5 g/kg protein and a share of about 30 kcal/kg a day."
                : "No daily targets or weigh-ins yet, so this assumes 80 kg: 0.5 g/kg protein, about 30 kcal/kg a day."
        }
        if target.light { return "You're at today's calories, so this is a light plate that's mostly protein." }
        let kcal = Int(left?.kcal ?? 0).formatted(), protein = Int(left?.protein ?? 0).formatted()
        let meals = target.mealsLeft == 1 ? "for this last meal" : "over \(target.mealsLeft) meals"
        return "\(kcal) kcal and \(protein) g protein left today, \(meals)."
    }

    /// `last` carries the footer on how plates are picked.
    private func hallSection(_ plan: HallPlan, best: Bool, last: Bool) -> some View {
        Section {
            if let plate = plan.plate, let target {
                Button { picked = HallPlate(hall: plan.hall, plate: plate) } label: {
                    PlateLabel(plate: plate, reason: DiningPlanner.reason(plate, for: target), logged: logged.contains(plan.id))
                }
                .tint(.primary)
            } else {
                Text(plan.failed ? "Couldn't load the menu." : plan.posted ? "Nothing on today's \(meal) menu has enough protein for a plate." : "No \(meal) menu posted today.")
                    .foregroundStyle(.secondary)
            }
            NavigationLink { HallMenuView(hall: plan.hall) } label: { Text("Full menu").font(.subheadline) }
        } header: {
            HStack {
                Text(plan.hall.name)
                Spacer()
                if best && plan.plate != nil { Text("Best fit").foregroundStyle(.green) }
            }
        } footer: {
            if last {
                Text("Protein per meal is 0.4–0.55 g per kg of body weight, the range that maximises muscle growth (Schoenfeld & Aragon, 2018). Plates favour lean protein and vegetables, and leave out fried food, desserts and the build-your-own bars. Tap a plate to log it.")
            }
        }
    }

    private func load() async {
        let meal = meal
        let start = EnergyTargets.historyStart() ?? Calendar.current.startOfDay(for: .now)
        let healthDays = await health.dailyNutrition(from: start, to: .now)
        let daily = EnergyTargets(metrics: metrics, logs: logs, health: healthDays, sex: Advanced.Sex(pref: sexRaw),
                                  unit: WeightUnit(rawValue: unitRaw) ?? .lb, from: start)?[.now]
            .map { DiningPlanner.Macros(kcal: Double($0.kcal), protein: Double($0.protein), carbs: Double($0.carbs), fat: Double($0.fat)) }
        let today = HealthService.Nutrition.eaten(on: .now, logs: logs, health: healthDays)
        let eaten = DiningPlanner.Macros(kcal: today.kcal, protein: today.protein, carbs: today.carbs, fat: today.fat)
        let weight = metrics.first { $0.deletedAt == nil && $0.bodyWeight != nil }.flatMap { m in m.bodyWeight.map { m.unit.convert($0, to: .kg) } }
        let target = DiningPlanner.target(daily: daily, eaten: eaten, bodyWeightKg: weight, meal: meal)
        guard !Task.isCancelled else { return }
        self.target = target
        left = daily.map { DiningPlanner.Macros(kcal: max(0, $0.kcal - eaten.kcal), protein: max(0, $0.protein - eaten.protein)) }

        // Each hall's menu and plate in parallel, off the main thread; then ranked by how well the plate fits.
        let plans = await withTaskGroup(of: HallPlan.self) { group in
            for hall in DiningService.halls where hall.meals.contains(meal) {
                group.addTask {
                    do {
                        let items = try await DiningService.menu(hall: hall.id, meal: meal)
                        return HallPlan(hall: hall, plate: DiningPlanner.bestPlate(items, for: target), posted: !items.isEmpty)
                    } catch {
                        return HallPlan(hall: hall, failed: true)
                    }
                }
            }
            var out: [HallPlan] = []
            for await plan in group { out.append(plan) }
            return out
        }
        guard !Task.isCancelled else { return }
        let order = DiningService.halls.map(\.id)
        results = (meal, plans.sorted {
            ($0.plate?.penalty ?? .infinity, order.firstIndex(of: $0.id) ?? 0) < ($1.plate?.penalty ?? .infinity, order.firstIndex(of: $1.id) ?? 0)
        })
    }
}

/// A recommended plate: each item with its servings, and why it fits.
private struct PlateLabel: View {
    let plate: DiningPlanner.Plate
    let reason: String
    let logged: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(plate.portions) { portion in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Format.number(portion.servings))×")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(minWidth: 30, alignment: .trailing)
                        Text(portion.item.name)
                    }
                }
                Text(reason).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
            Spacer(minLength: 8)
            Image(systemName: logged ? "checkmark.circle.fill" : "plus.circle")
                .font(.title3)
                .foregroundStyle(logged ? Color.green : Color.accentColor)
                .accessibilityLabel(logged ? "Logged" : "Log this plate")
        }
        .padding(.vertical, 2)
    }
}

/// Confirms a plate before logging each item as dining food from the hall; servings can be changed (0 leaves one out).
struct LogPlateSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let hall: DiningHall
    let onLog: () -> Void
    @State private var portions: [DiningPlanner.Portion]
    @State private var meal: Meal

    init(hall: DiningHall, plate: DiningPlanner.Plate, meal: Meal, onLog: @escaping () -> Void) {
        self.hall = hall
        self.onLog = onLog
        _portions = State(initialValue: plate.portions)
        _meal = State(initialValue: meal)
    }

    private var total: DiningPlanner.Macros {
        portions.reduce(DiningPlanner.Macros()) { $0 + DiningPlanner.tally($1.item, servings: $1.servings).macros }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($portions) { $portion in
                        Stepper(value: $portion.servings, in: 0...10, step: 0.5) {
                            VStack(alignment: .leading) {
                                Text(portion.item.name)
                                Text("\(Format.number(portion.servings)) × \(portion.item.serving)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    let t = [total.kcal, total.protein, total.carbs, total.fat].map { Int($0.rounded()).formatted() }
                    Text("\(t[0]) kcal · \(t[1]) g protein · \(t[2]) g carbs · \(t[3]) g fat").monospacedDigit()
                }
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.label).tag($0) }
                }
            }
            .navigationTitle(hall.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { log() }.disabled(!portions.contains { $0.servings > 0 })
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func log() {
        let now = Date()
        for p in portions where p.servings > 0 {
            context.insert(FoodLog(
                eatenAt: now, meal: meal.rawValue, source: "dining", place: hall.name, name: p.item.name, serving: p.item.serving,
                servings: p.servings, kcal: p.item.kcal, protein: p.item.protein, carbs: p.item.carbs, fat: p.item.fat
            ))
        }
        try? context.save()
        onLog()
        dismiss()
    }
}
