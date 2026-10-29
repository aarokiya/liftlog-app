import LiftKit
import SwiftData
import SwiftUI

/// Food → Dining hall (pick hall → today's menu + always-available staples) or Outside (fast food / custom).
struct FoodView: View {
    @Query(filter: #Predicate<FoodLog> { $0.deletedAt == nil }, sort: \FoodLog.eatenAt, order: .reverse) private var logs: [FoodLog]
    @Query(sort: \BodyMetric.measuredAt, order: .reverse) private var metrics: [BodyMetric]
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @AppStorage(Prefs.campus) private var campus = ""
    @AppStorage(Prefs.sex) private var sexRaw = ""
    @Query(filter: #Predicate<WaterLog> { $0.deletedAt == nil }, sort: \WaterLog.drankAt, order: .reverse) private var waterLogs: [WaterLog]
    @Query(filter: #Predicate<Workout> { $0.deletedAt == nil }, sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @State private var healthToday: HealthService.Nutrition?
    @State private var customWater = ""
    @State private var enteringWater = false

    private var today: [FoodLog] { logs.filter { Calendar.current.isDateInToday($0.eatenAt) } }
    private var waterToday: [WaterLog] { waterLogs.filter { Calendar.current.isDateInToday($0.drankAt) } }
    private var waterUnit: WaterUnit { .preferred(for: WeightUnit(rawValue: unitRaw) ?? .lb) }

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

    private func logged(_ key: KeyPath<FoodLog, Double>) -> Double {
        today.reduce(0) { $0 + $1[keyPath: key] * $1.servings }
    }

    private func total(_ key: KeyPath<FoodLog, Double>, _ healthKey: KeyPath<HealthService.Nutrition, Double>) -> Double {
        logged(key) + (healthToday?[keyPath: healthKey] ?? 0)
    }

    private var proteinTarget: Int? {
        let live = metrics.filter { $0.deletedAt == nil }
        guard let sex = Advanced.Sex(pref: sexRaw), let bf = live.first(where: { $0.bodyFatPct != nil })?.bodyFatPct,
              let entry = live.first(where: { $0.bodyWeight != nil }), let bw = entry.bodyWeight else { return nil }
        let unit = WeightUnit(rawValue: unitRaw) ?? .lb
        return Aesthetics.bodyPlan(bodyWeight: entry.unit.convert(bw, to: unit), unit: unit, bodyFatPct: bf,
                                   startWeight: live.planStartWeight(in: unit), sex: sex).proteinG
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        macro("kcal", total(\.kcal, \.kcal))
                        macro("protein", total(\.protein, \.protein), target: proteinTarget)
                        macro("carbs", total(\.carbs, \.carbs))
                        macro("fat", total(\.fat, \.fat))
                    }
                    if let healthToday {
                        LabeledContent("Logged in LiftLog", value: "\(Int(logged(\.kcal).rounded())) kcal · \(Int(logged(\.protein).rounded())) g P")
                        LabeledContent("From Apple Health", value: "\(Int(healthToday.kcal.rounded())) kcal · \(Int(healthToday.protein.rounded())) g P")
                    }
                } header: {
                    Text("Today")
                } footer: {
                    if healthToday != nil {
                        Text("Includes what MyFitnessPal or other apps saved to Apple Health. Log each meal in one app only so it isn't counted twice.")
                    }
                }
                Section("Add food") {
                    if campus == "gatech" {
                        NavigationLink { HallPicker() } label: { Label("Dining hall", systemImage: "building.columns") }
                    }
                    NavigationLink { OutsideFoodView() } label: { Label("Outside food", systemImage: "takeoutbag.and.cup.and.straw") }
                    NavigationLink { FoodSearchView() } label: { Label("Search all foods / scan barcode", systemImage: "magnifyingglass") }
                }
                if !today.isEmpty {
                    Section("Logged today") {
                        ForEach(today) { log in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(log.name).lineLimit(1)
                                    Text("\(log.place ?? log.source.capitalized) · \(Meal(rawValue: log.meal)?.label ?? log.meal) · \(Format.number(log.servings))×")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int((log.kcal * log.servings).rounded())) kcal · \(Int((log.protein * log.servings).rounded())) g P")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        .onDelete { offsets in
                            let rows = today
                            for i in offsets { rows[i].softDelete() }
                        }
                    }
                }
                waterSection
            }
            .navigationTitle("Food")
            .alert("Add water", isPresented: $enteringWater) {
                TextField("Amount (\(waterUnit.rawValue))", text: $customWater)
                    .keyboardType(.decimalPad)
                Button("Add") {
                    addWater(Double(customWater.replacingOccurrences(of: ",", with: ".")) ?? 0)
                    customWater = ""
                }
                Button("Cancel", role: .cancel) { customWater = "" }
            }
            .task { healthToday = await health.nutrition(on: .now) }
            .refreshable { healthToday = await health.nutrition(on: .now) }
        }
    }

    private var waterSection: some View {
        let unit = waterUnit
        let total = waterToday.reduce(0) { $0 + $1.unit.convert($1.amount, to: unit) }
        let shown = (total * 10).rounded() / 10
        return Section("Water") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "drop.fill").foregroundStyle(.cyan)
                    Text(Format.number(shown)).font(.title2.bold().monospacedDigit())
                    Text("\(unit.rawValue) today").foregroundStyle(.secondary)
                    if let goal = waterGoal {
                        Spacer()
                        Text("goal \(Format.number(goal))")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(shown >= goal ? Goal.hit.color : Goal.missed.color)
                    }
                }
                if let goal = waterGoal {
                    ProgressView(value: min(shown, goal), total: goal).tint(shown >= goal ? Goal.hit.color : Goal.missed.color)
                } else {
                    Text("Log your body weight in Settings → Body & aesthetics to get a daily goal.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(unit.quickAmounts, id: \.self) { amount in
                        Button { addWater(amount) } label: {
                            Text("+\(Format.number(amount))").font(.subheadline.monospacedDigit()).frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Add \(Format.number(amount)) \(unit.rawValue)")
                    }
                    Button { enteringWater = true } label: {
                        Image(systemName: "ellipsis").frame(minHeight: 17)
                    }
                    .accessibilityLabel("Other amount")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.cyan)
            }
            .padding(.vertical, 4)
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
        }
    }

    private func macro(_ label: String, _ value: Double, target: Int? = nil) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value.rounded()))").font(.headline.monospacedDigit())
                .foregroundStyle(target.map { value.rounded() >= Double($0) ? Goal.hit.color : Goal.missed.color } ?? .primary)
            Text(target.map { "\(label) / \($0)" } ?? label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HallPicker: View {
    var body: some View {
        List(DiningService.halls) { hall in
            NavigationLink(hall.name) { HallMenuView(hall: hall) }
        }
        .navigationTitle("Dining hall")
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
        .sheet(item: $picked) { item in
            LogFoodSheet(item: item, source: "dining", place: hall.name, meal: Meal(rawValue: meal) ?? .snack)
        }
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
        .sheet(item: $picked) { item in LogFoodSheet(item: item, source: "outside", place: item.brand, meal: .current()) }
        .sheet(isPresented: $addingCustom) { CustomFoodSheet() }
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
        .sheet(item: $picked) { item in LogFoodSheet(item: item, source: "outside", place: brand.name, meal: .current()) }
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
        .sheet(item: $picked) { item in LogFoodSheet(item: item, source: "outside", place: brand, meal: .current()) }
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
                    Text("\(Int(item.kcal.rounded())) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                    Text("\(Format.number(item.protein)) g protein").font(.caption).foregroundStyle(.secondary)
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
    @State private var name = ""
    @State private var place = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var meal = Meal.current()

    var body: some View {
        NavigationStack {
            Form {
                TextField("What did you eat?", text: $name)
                TextField("Where (optional)", text: $place)
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.label).tag($0) }
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
                    Button("Log") {
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
