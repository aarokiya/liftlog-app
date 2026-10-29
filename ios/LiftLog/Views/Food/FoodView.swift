import LiftKit
import SwiftData
import SwiftUI

/// Food → Georgia Tech (dining halls' menus, campus places, nearby restaurants), Outside (fast food / custom) or search.
struct FoodView: View {
    @Query(filter: #Predicate<FoodLog> { $0.deletedAt == nil }, sort: \FoodLog.eatenAt, order: .reverse) private var logs: [FoodLog]
    @Query(sort: \BodyMetric.measuredAt, order: .reverse) private var metrics: [BodyMetric]
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @AppStorage(Prefs.sex) private var sexRaw = ""
    @Query(filter: #Predicate<WaterLog> { $0.deletedAt == nil }, sort: \WaterLog.drankAt, order: .reverse) private var waterLogs: [WaterLog]
    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil }, sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthService.self) private var health
    @Environment(Reminders.self) private var reminders
    /// What other apps saved to Health per day, for the targets and the calendar; one load covers both.
    @State private var healthDays: [Date: HealthService.Nutrition] = [:]
    /// Health's step count per day (start of day), from 28 days before `rangeStart` so every day shown has its goal.
    @State private var steps: [Date: Double] = [:]
    /// The month the goals calendar shows.
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    /// The day picked in the goals calendar; a past day lists its logged foods under it.
    @State private var day = Calendar.current.startOfDay(for: .now)
    /// The logged food being edited.
    @State private var editing: FoodLog?
    @State private var customWater = ""
    @State private var enteringWater = false
    /// The water buttons take water away instead of adding it.
    @State private var removingWater = false

    private var today: [FoodLog] { logs.filter { Calendar.current.isDateInToday($0.eatenAt) } }
    private var dayLogs: [FoodLog] { logs.filter { Calendar.current.isDate($0.eatenAt, inSameDayAs: day) } }
    private var healthToday: HealthService.Nutrition? { healthDays[Calendar.current.startOfDay(for: .now)] }
    private var waterToday: [WaterLog] { waterLogs.filter { Calendar.current.isDateInToday($0.drankAt) } }
    private var waterUnit: WaterUnit { .preferred(for: WeightUnit(rawValue: unitRaw) ?? .lb) }
    private var waterTotal: Double { waterToday.reduce(0) { $0 + $1.unit.convert($1.amount, to: waterUnit) } }

    private var waterGoal: Double? {
        guard let entry = metrics.first(where: { $0.deletedAt == nil && $0.bodyWeight != nil }), let bw = entry.bodyWeight else { return nil }
        let trained = workouts.prefix(3).contains { Calendar.current.isDateInToday($0.startedAt) }
        return waterUnit.dailyGoal(bodyWeightKg: entry.unit.convert(bw, to: .kg), trained: trained)
    }

    private func addWater(_ raw: Double) {
        // The column keeps one decimal; round first so a tiny amount can't become a 0 the server rejects.
        let amount = (raw * 10).rounded() / 10
        guard amount > 0, amount <= 5000 else { return }
        context.insert(WaterLog(amount: amount, unit: waterUnit))
        try? context.save()
    }

    /// Takes `raw` (in the display unit) off today's water, newest log first: whole logs are deleted and the last one
    /// touched is shortened, so every stored amount stays positive.
    private func removeWater(_ raw: Double) {
        var left = raw
        for log in waterToday where left > 0.05 {
            let shown = log.unit.convert(log.amount, to: waterUnit)
            if shown <= left + 0.05 {
                log.softDelete()
                left -= shown
            } else {
                let rest = (waterUnit.convert(shown - left, to: log.unit) * 10).rounded() / 10
                if rest > 0 {
                    log.amount = rest
                    log.touch()
                } else {
                    log.softDelete()
                }
                left = 0
            }
        }
        try? context.save()
    }

    private func logged(_ key: KeyPath<FoodLog, Double>) -> Double {
        today.reduce(0) { $0 + $1[keyPath: key] * $1.servings }
    }

    private func total(_ key: KeyPath<FoodLog, Double>, _ healthKey: KeyPath<HealthService.Nutrition, Double>) -> Double {
        logged(key) + (healthToday?[keyPath: healthKey] ?? 0)
    }

    /// Targets run from the calendar's first day, or 33 days back so maintenance and carryover have their history.
    private var rangeStart: Date {
        min(month, EnergyTargets.historyStart() ?? month)
    }

    private func loadHealth() async {
        healthDays = await health.dailyNutrition(from: rangeStart, to: .now)
        steps = await health.dailySteps(from: Calendar.current.date(byAdding: .day, value: -28, to: rangeStart) ?? rangeStart, to: .now)
    }

    /// Today's totals; the reminders are rebuilt when they change.
    private var todayTotals: [Double] {
        [total(\.kcal, \.kcal), total(\.protein, \.protein), total(\.carbs, \.carbs), total(\.fat, \.fat), waterTotal]
    }

    private func refreshReminders() {
        reminders.refresh(context: context, health: health, healthDays: healthDays)
    }

    var body: some View {
        let energy = EnergyTargets(metrics: metrics, logs: logs, health: healthDays, sex: Advanced.Sex(pref: sexRaw),
                                   unit: WeightUnit(rawValue: unitRaw) ?? .lb, from: rangeStart)
        let targets = energy?[.now]
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        macro("Calories", total(\.kcal, \.kcal), target: targets?.kcal, unit: "")
                        let protein = total(\.protein, \.protein)
                        // Protein is a minimum: more is fine.
                        GoalBar(label: "Protein", value: protein, target: targets.map { Double($0.protein) }, unit: "g",
                                state: targets.flatMap { Goal.reaching(protein, Double($0.protein)) })
                        macro("Carbs", total(\.carbs, \.carbs), target: targets?.carbs, unit: "g")
                        macro("Fat", total(\.fat, \.fat), target: targets?.fat, unit: "g")
                        stepsRow
                    }
                    .padding(.vertical, 6)
                    if let healthToday {
                        Group {
                            LabeledContent("Logged in LiftLog", value: "\(Int(logged(\.kcal).rounded()).formatted()) kcal · \(Int(logged(\.protein).rounded())) g protein")
                            LabeledContent("From Apple Health", value: "\(Int(healthToday.kcal.rounded()).formatted()) kcal · \(Int(healthToday.protein.rounded())) g protein")
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text([
                        energy.map { "Maintenance ≈ \($0.maintenance.formatted()) kcal, \($0.learned ? "learned from your logs" : "estimated"). Targets adjust for your last 3 days." }
                            ?? "Set your sex and log your weight and a body-fat % in Settings → Body & aesthetics to get daily targets.",
                        healthToday == nil ? nil : "Includes food other apps saved to Apple Health; log each meal in one app only.",
                        stepsNote,
                    ].compactMap { $0 }.joined(separator: " "))
                }
                Section("Add food") {
                    AddFoodLinks()
                }
                if !today.isEmpty {
                    Section("Logged today") {
                        ForEach(today) { log in
                            LoggedFoodRow(log: log) { editing = log }
                        }
                        .onDelete { offsets in
                            let rows = today
                            for i in offsets { rows[i].softDelete() }
                        }
                    }
                }
                waterSection
                Section("Daily goals") {
                    GoalCalendar(month: $month, selected: $day, logs: logs, waterLogs: waterLogs, workouts: workouts, metrics: metrics,
                                 waterUnit: waterUnit, healthDays: healthDays, steps: steps, targets: energy)
                }
                if !Calendar.current.isDateInToday(day), !dayLogs.isEmpty {
                    Section("Logged on \(day.formatted(.dateTime.weekday().month().day()))") {
                        ForEach(dayLogs) { log in
                            LoggedFoodRow(log: log) { editing = log }
                        }
                        .onDelete { offsets in
                            let rows = dayLogs
                            for i in offsets { rows[i].softDelete() }
                        }
                    }
                }
            }
            .navigationTitle("Food")
            .alert(removingWater ? "Remove water" : "Add water", isPresented: $enteringWater) {
                TextField("Amount (\(waterUnit.rawValue))", text: $customWater)
                    .keyboardType(.decimalPad)
                Button(removingWater ? "Remove" : "Add") {
                    let amount = Double(customWater.replacingOccurrences(of: ",", with: ".")) ?? 0
                    if removingWater { removeWater(amount) } else { addWater(amount) }
                    customWater = ""
                }
                Button("Cancel", role: .cancel) { customWater = "" }
            }
            .sheet(item: $editing) { EditFoodLogSheet(log: $0) }
            .task(id: month) { await loadHealth() }
            .refreshable { await loadHealth() }
            // Steps keep counting while LiftLog is in the background, and Health may have just been turned on.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadHealth() } }
            }
            .onChange(of: health.isEnabled) { Task { await loadHealth() } }
            .onChange(of: todayTotals) { refreshReminders() }
            .onChange(of: healthDays) { refreshReminders() }
        }
    }

    private var waterSection: some View {
        let unit = waterUnit
        let shown = (waterTotal * 10).rounded() / 10
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                GoalBar(value: shown, target: waterGoal, unit: unit.rawValue, state: waterGoal.flatMap { Goal.reaching(shown, $0) },
                        format: Format.number)
                if waterGoal == nil {
                    Text("Log your body weight in Settings → Body & aesthetics to get a daily goal.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(unit.quickAmounts, id: \.self) { amount in
                        Button { removingWater ? removeWater(amount) : addWater(amount) } label: {
                            Text("\(removingWater ? "−" : "+")\(Format.number(amount))").font(.subheadline.monospacedDigit()).frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("\(removingWater ? "Remove" : "Add") \(Format.number(amount)) \(unit.rawValue)")
                    }
                    Button { enteringWater = true } label: {
                        Image(systemName: "ellipsis").frame(minHeight: 17)
                    }
                    .accessibilityLabel("Other amount")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(removingWater ? .red : .cyan)
                .disabled(removingWater && waterToday.isEmpty)
            }
            .padding(.vertical, 6)
            if !waterToday.isEmpty {
                DisclosureGroup("Today's log (\(waterToday.count))") {
                    ForEach(waterToday) { log in
                        LabeledContent(log.drankAt.formatted(date: .omitted, time: .shortened), value: "\(Format.number(log.amount)) \(log.unit.rawValue)")
                    }
                    .onDelete { offsets in
                        let rows = waterToday
                        for i in offsets { rows[i].softDelete() }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Water")
                Spacer()
                Button { removingWater.toggle() } label: {
                    Image(systemName: removingWater ? "plus.circle.fill" : "minus.circle")
                        .font(.title3)
                        .foregroundStyle(removingWater ? .cyan : .red)
                }
                .accessibilityLabel(removingWater ? "Back to adding water" : "Remove water")
            }
        }
    }

    /// Today's steps from Apple Health against a goal from your own recent days (`Steps.goal`), under the macros. They
    /// stay on the phone.
    @ViewBuilder private var stepsRow: some View {
        if HealthService.isAvailable {
            let now = Calendar.current.startOfDay(for: .now)
            if !health.isEnabled {
                Button {
                    Task {
                        await health.enable()
                        await health.sync(context: context)
                    }
                } label: {
                    Label("Connect Apple Health for steps", systemImage: "figure.walk")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            } else if steps.isEmpty {
                Text("No steps from Apple Health yet. Check that LiftLog can read Steps in the Health app → your profile → Apps.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let count = steps[now] ?? 0
                let goal = Double(Steps.goal(steps, on: now))
                GoalBar(label: "Steps", value: count, target: goal, state: Goal.reaching(count, goal))
            }
        }
    }

    /// Where today's step goal comes from, for the Today footer.
    private var stepsNote: String? {
        guard HealthService.isAvailable, health.isEnabled, !steps.isEmpty else { return nil }
        let now = Calendar.current.startOfDay(for: .now)
        return Steps.baseline(steps, on: now).map { "Step goal: your typical day lately (\(Int($0.rounded()).formatted())) plus 10%." }
            ?? "Step goal: \(Steps.defaultGoal.formatted()) until Apple Health has a week of steps."
    }

    /// Today's calories, carbs or fat: green within 10% of the target, red once more than 10% over, neutral while under.
    private func macro(_ label: String, _ value: Double, target: Int?, unit: String) -> some View {
        GoalBar(label: label, value: value, target: target.map(Double.init), unit: unit,
                state: target.flatMap { Goal.soFar(value, Double($0)) })
    }
}

struct HallMenuView: View {
    let hall: DiningHall
    @State private var meal = Meal.current().rawValue
    @State private var items: [FoodItem] = []
    @State private var loading = false
    @State private var failed = false
    @State private var search = ""
    @State private var picked: FoodItem?

    private func matches(_ list: [FoodItem]) -> [FoodItem] {
        search.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Picker("Meal", selection: $meal) {
                ForEach(hall.meals, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            if loading {
                ProgressView("Loading today's menu")
            } else if failed {
                Text("Couldn't load the menu. Staples are below.").foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("No menu posted for this meal today.").foregroundStyle(.secondary)
            }
            ForEach(FoodGroup.by(\.station, matches(items))) { group in
                Section(group.id) {
                    ForEach(group.items) { item in FoodRow(item: item) { picked = item } }
                }
            }
            ForEach(FoodGroup.by(\.station, matches(FoodLibrary.staples))) { group in
                Section("Always available · \(group.id)") {
                    ForEach(group.items) { item in FoodRow(item: item) { picked = item } }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search the menu")
        .navigationTitle(hall.name)
        .task(id: meal) { await load() }
        .logFoodSheet($picked, source: "dining", place: { _ in hall.name }, meal: Meal(rawValue: meal) ?? .snack)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await DiningService.menu(hall: hall.id, meal: meal)
            failed = false
        } catch {
            items = []
            failed = true
        }
    }
}

struct OutsideFoodView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.foodPick) private var pick
    @State private var search = ""
    @State private var picked: FoodItem?
    @State private var addingCustom = false
    @State private var packaged: [FoodItem] = []

    var body: some View {
        List {
            Section {
                Button { addingCustom = true } label: { Label("Custom food (enter macros)", systemImage: "square.and.pencil") }
            }
            if search.isEmpty {
                Section("Restaurants") {
                    ForEach(FoodLibrary.restaurants, id: \.self) { brand in
                        NavigationLink(brand) { BrandMenuView(brand: brand) }
                    }
                }
                if auth.isSignedIn {
                    ForEach(FoodLibrary.snackGroups) { group in
                        Section(group.name) {
                            ForEach(group.brands, id: \.self) { brand in
                                NavigationLink(brand.name) { SnackBrandView(brand: brand) }
                            }
                        }
                    }
                } else {
                    Section("Snacks & drinks") {
                        Text("Sign in (Settings → Sign in to sync) to browse snack and drink brands from the food databank.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                if !auth.isSignedIn {
                    Text("Sign in to also search snacks, drinks and packaged foods.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Restaurants") {
                    ForEach(FoodLibrary.fastFood.filter {
                        $0.name.localizedCaseInsensitiveContains(search) || ($0.brand ?? "").localizedCaseInsensitiveContains(search)
                    }.prefix(100)) { item in
                        FoodRow(item: item, showBrand: true) { picked = item }
                    }
                }
                if !packaged.isEmpty {
                    Section("Snacks, drinks & packaged foods") {
                        ForEach(packaged) { item in
                            FoodRow(item: item, showBrand: item.brand != nil) { picked = item }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search restaurants and snacks")
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(350))
            let q = search.trimmingCharacters(in: .whitespaces)
            guard !Task.isCancelled, q.count >= 2, auth.isSignedIn, let client = auth.client else {
                packaged = []
                return
            }
            let results = (try? await FoodDatabank.search(q, client: client)) ?? []
            if !Task.isCancelled { packaged = results.uniqued() }
        }
        .navigationTitle("Outside food")
        .logFoodSheet($picked, source: "outside", place: \.brand)
        .sheet(isPresented: $addingCustom) { CustomFoodSheet(pick: pick) }
    }
}

/// A snack or drink brand's products from the foods databank.
struct SnackBrandView: View {
    let brand: SnackBrand
    @Environment(AuthService.self) private var auth
    @State private var items: [FoodItem] = []
    @State private var loading = true
    @State private var message: String?
    @State private var picked: FoodItem?

    var body: some View {
        List {
            if loading { ProgressView() }
            if let message { Text(message).foregroundStyle(.secondary) }
            ForEach(items) { item in
                FoodRow(item: item) { picked = item }
            }
        }
        .navigationTitle(brand.name)
        .task {
            defer { loading = false }
            guard let client = auth.client, auth.isSignedIn else {
                message = "Sign in to browse snacks from the food databank."
                return
            }
            do {
                items = brand.filter(try await FoodDatabank.search(brand.q, client: client).uniqued())
                message = items.isEmpty ? "Nothing found. Try Search all foods." : nil
            } catch {
                message = "Couldn't load: \(error.localizedDescription)"
            }
        }
        .logFoodSheet($picked, source: "outside", place: { _ in brand.name })
    }
}

struct BrandMenuView: View {
    let brand: String
    @State private var picked: FoodItem?

    var body: some View {
        List(FoodLibrary.fastFood.filter { $0.brand == brand }) { item in
            FoodRow(item: item) { picked = item }
        }
        .navigationTitle(brand)
        .logFoodSheet($picked, source: "outside", place: { _ in brand })
    }
}

struct FoodRow: View {
    let item: FoodItem
    var showBrand = false
    let action: () -> Void

    /// "Brand Name", unless the name already starts with the brand ("Chick-fil-A Nuggets").
    private var title: String {
        guard showBrand, let brand = item.brand, !brand.isEmpty,
              !item.name.lowercased().hasPrefix(brand.lowercased()) else { return item.name }
        return "\(brand) \(item.name)"
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(.primary)
                    Text(item.serving).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(item.estimated == true ? "≈ " : "")\(Int(item.kcal.rounded())) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                    Text("\(Format.number(item.protein)) g protein").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
    }
}

/// A logged food on the Food screen; tap to edit it.
struct LoggedFoodRow: View {
    let log: FoodLog
    let action: () -> Void

    /// Where it's from and the meal, plus the servings when it isn't one.
    private var details: String {
        [log.place ?? log.source.capitalized, Meal(rawValue: log.meal)?.label ?? log.meal, log.servings == 1 ? nil : "\(Format.number(log.servings))×"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(log.name).foregroundStyle(.primary).lineLimit(1)
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(Int((log.kcal * log.servings).rounded())) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                    Text("\(Format.number(log.protein * log.servings)) g protein").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
    }
}

struct LogFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: FoodItem
    let source: String
    let place: String?
    @State private var meal: Meal
    @State private var servings = 1.0

    init(item: FoodItem, source: String, place: String?, meal: Meal) {
        self.item = item
        self.source = source
        self.place = place
        _meal = State(initialValue: meal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.name).font(.headline)
                    Text(item.serving).foregroundStyle(.secondary)
                }
                Section {
                    Stepper("\(Format.number(servings)) serving\(servings == 1 ? "" : "s")", value: $servings, in: 0.5...10, step: 0.5)
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Total") {
                    LabeledContent("Calories", value: "\(Int((item.kcal * servings).rounded()))")
                    LabeledContent("Protein", value: "\(Format.number(item.protein * servings)) g")
                    LabeledContent("Carbs", value: "\(Format.number(item.carbs * servings)) g")
                    LabeledContent("Fat", value: "\(Format.number(item.fat * servings)) g")
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log") { log() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func log() {
        context.insert(FoodLog(
            meal: meal.rawValue, source: source, place: place, name: item.name, serving: item.serving,
            servings: servings, kcal: item.kcal, protein: item.protein, carbs: item.carbs, fat: item.fat
        ))
        try? context.save()
        dismiss()
    }
}

struct CustomFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Set while replacing a logged food: the food goes back to the edit sheet instead of being logged.
    var pick: FoodPick?
    @State private var name = ""
    @State private var place: String
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var meal = Meal.current()

    /// `place` prefills "Where", e.g. a campus place with no published menu.
    init(pick: FoodPick? = nil, place: String = "") {
        self.pick = pick
        _place = State(initialValue: place)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What did you eat?", text: $name)
                TextField("Where (optional)", text: $place)
                if pick == nil {
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Macros") {
                    TextField("Calories", value: $kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Protein (g)", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbs (g)", value: $carbs, format: .number).keyboardType(.decimalPad)
                    TextField("Fat (g)", value: $fat, format: .number).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Custom food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pick == nil ? "Log" : "Use") {
                        if let pick {
                            let item = FoodItem(id: UUID().uuidString, name: name, serving: "", kcal: max(0, kcal ?? 0),
                                                protein: max(0, protein ?? 0), carbs: max(0, carbs ?? 0), fat: max(0, fat ?? 0))
                            dismiss()
                            pick(item, "custom", place.isEmpty ? nil : place)
                            return
                        }
                        context.insert(FoodLog(
                            meal: meal.rawValue, source: "custom", place: place.isEmpty ? nil : place, name: name, serving: nil,
                            kcal: max(0, kcal ?? 0), protein: max(0, protein ?? 0), carbs: max(0, carbs ?? 0), fat: max(0, fat ?? 0)
                        ))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
