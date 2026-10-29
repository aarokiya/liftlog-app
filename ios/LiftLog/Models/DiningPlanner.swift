import Foundation

/// Picks a plate from a dining hall's menu for one meal: a protein, plus a starch, a vegetable and a second protein when
/// they help, with servings chosen to reach the meal's protein and fit its calories. Pure functions throughout.
///
/// Protein per meal follows Schoenfeld & Aragon 2018: about 0.4 g/kg a meal maximises muscle protein synthesis, and
/// 0.55 g/kg a meal is the top of the useful range (2.2 g/kg a day over 4 meals). Saturated fat and added sugar are scored
/// against the Dietary Guidelines' 10% of calories each.
enum DiningPlanner {
    /// Calories and grams of protein, carbs and fat.
    struct Macros: Equatable {
        var kcal = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0

        static func + (a: Macros, b: Macros) -> Macros {
            Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
        }
    }

    /// What one meal should hit.
    struct Target: Equatable {
        var kcal: Double
        /// Grams to aim for: what's left of today's protein spread over the meals left, within 0.4–0.55 g/kg.
        var protein: Double
        /// 0.4 g/kg.
        var proteinMin: Double
        var carbs: Double
        var fat: Double
        /// Main meals left today, this one included.
        var mealsLeft: Int
        /// No daily targets: body-weight protein and a share of an estimated day.
        var estimated: Bool
        /// Today's calories are used up, so the plate is light and mostly protein.
        var light: Bool
    }

    /// One item and how many of its servings.
    struct Portion: Identifiable, Hashable {
        let item: FoodItem
        var servings: Double
        var id: String { item.id }
    }

    /// A plate's totals and the counts its score looks at.
    struct Tally: Equatable {
        var macros = Macros()
        var saturatedFat = 0.0
        var addedSugar = 0.0
        var fiber = 0.0
        var fried = 0
        var desserts = 0
        var vegetables = 0
        var items = 0
        /// The protein items' share: how lean they are.
        var proteinFoods = Macros()

        static func + (a: Tally, b: Tally) -> Tally {
            Tally(
                macros: a.macros + b.macros, saturatedFat: a.saturatedFat + b.saturatedFat, addedSugar: a.addedSugar + b.addedSugar,
                fiber: a.fiber + b.fiber, fried: a.fried + b.fried, desserts: a.desserts + b.desserts,
                vegetables: a.vegetables + b.vegetables, items: a.items + b.items, proteinFoods: a.proteinFoods + b.proteinFoods
            )
        }
    }

    struct Plate: Equatable {
        let portions: [Portion]
        let tally: Tally
        /// Lower is better; see `penalty`.
        let penalty: Double
    }

    /// What an item can be on a plate.
    enum Role { case protein, starch, vegetable, other }

    // MARK: - The meal's target

    /// Main meals left today from `meal` on, this one included: breakfast 3, lunch 2, dinner (or overnight) 1.
    static func mealsLeft(_ meal: String) -> Int {
        switch meal {
        case "breakfast": 3
        case "lunch": 2
        default: 1
        }
    }

    /// Without daily targets a day is about 30 kcal/kg (roughly maintenance for someone who lifts), and protein is 0.5 g/kg
    /// a meal. Without a weigh-in either, 80 kg stands in.
    static let fallbackKcalPerKg = 30.0
    static let fallbackKg = 80.0

    /// `daily` is today's targets (nil without a plan); `eaten` is everything logged today so far.
    static func target(daily: Macros?, eaten: Macros, bodyWeightKg: Double?, meal: String) -> Target {
        let left = mealsLeft(meal)
        let n = Double(left)
        let kg = bodyWeightKg ?? fallbackKg
        let low = 0.4 * kg, high = 0.55 * kg
        let day = daily ?? Macros(kcal: fallbackKcalPerKg * kg)
        let protein = daily.map { min(max(($0.protein - eaten.protein) / n, low), high) } ?? 0.5 * kg
        // What's left of today's calories split evenly, at most half the day in one meal. Once they're used up, a light
        // plate where protein is about half the calories.
        let share = min((day.kcal - eaten.kcal) / n, day.kcal / 2)
        let lightKcal = 8 * protein
        let kcal = max(share, lightKcal)
        // Fat is what's left of today's (30% of the calories without targets), at most 35% of the meal; carbs fill the rest.
        let fatLeft = daily.map { max(0, $0.fat - eaten.fat) / n } ?? 0.3 * kcal / 9
        let fat = min(fatLeft, 0.35 * kcal / 9)
        let carbs = max(0, kcal - 4 * protein - 9 * fat) / 4
        return Target(kcal: kcal.rounded(), protein: protein.rounded(), proteinMin: low.rounded(), carbs: carbs.rounded(),
                      fat: fat.rounded(), mealsLeft: left, estimated: daily == nil, light: share < lightKcal)
    }

    // MARK: - Items

    /// A name ending in one of these is a condiment or spread, not food for a plate ("Lemon Dill Sauce", "Olive Oil").
    private static let condiments: Set<String> = [
        "dressing", "sauce", "vinaigrette", "mayo", "mayonnaise", "aioli", "oil", "vinegar", "mustard", "ketchup", "salsa", "pico",
        "relish", "syrup", "gravy", "seasoning", "spice", "spices", "oregano", "chutney", "powder", "crouton", "croutons", "jelly",
        "jam", "honey", "sprinkles", "butter", "margarine", "hummus", "guacamole", "cream", "base", "dip", "glaze", "spread",
    ]
    /// A name starting with one of these is a topping ("Shredded Parmesan Cheese").
    private static let toppings: Set<String> = ["shredded", "grated", "crumbled", "crumble", "crushed", "julienne", "julienned"]
    /// Build-your-own bars list single ingredients by the ounce, which don't make a plate on their own.
    private static let barStations = ["salad bar", "deli", "smoothie", "made to order", "cold bar", "condiment", "beverage", "drink"]
    private static let bulkUnits: Set<String> = [
        "lb", "lbs", "pound", "pounds", "gallon", "gallons", "quart", "quarts", "pan", "pans", "sheet", "loaf", "batch",
    ]

    // Keys match at the start of a word; one ending in a space must be the whole word.
    private static let friedWords = [
        "fried", "fries", "tempura", "crispy", "breaded", "battered", "tenders", "nugget", "tots", "tater", "pakora", "fritter",
        "doughnut", "donut", "popcorn", "puff", "chips", "corn dog", "katsu", "schnitzel", "hush pupp", "onion ring", "egg roll",
        "spring roll", "samosa", "churro", "croquette", "wings",
    ]
    private static let dessertWords = [
        "cookie", "cake", "cupcake", "cheesecake", "brownie", "muffin", "pastry", "pastries", "cobbler", "pudding", "sundae",
        "ice cream", "danish", "cinnamon roll", "treat", "fudge", "candy", "tart ", "tarts ", "eclair", "frosted", "glazed",
        "chocolate", "dole whip", "parfait", "scone", "crisp ",
    ]
    private static let vegetableWords = [
        "broccoli", "green bean", "carrot", "spinach", "kale", "zucchini", "squash", "cabbage", "brussel", "cauliflower", "vegetable",
        "veggie", "pepper", "asparagus", "greens", "collard", "okra", "eggplant", "mushroom", "tomato", "salad", "slaw", "peas ",
        "pea ", "corn ", "edamame", "bok choy", "medley", "ratatouille", "beet", "sprout", "chard", "celery", "cucumber", "lettuce",
        "romaine", "onion", "fruit", "apple", "banana", "berries", "blueberr", "strawberr", "melon", "watermelon", "cantaloupe",
        "honeydew", "orange", "pineapple", "grape", "peach", "pear ", "pears ",
    ]
    /// Grains and potatoes: a dish with these is a starch even if it has vegetables in it.
    private static let grainWords = [
        "rice", "pasta", "noodle", "spaghetti", "penne", "macaroni", "mac ", "potato", "bread", "bun ", "buns ", "roll ", "rolls ",
        "tortilla", "quinoa", "cous", "grits", "oat", "biscuit", "barley", "millet", "farro", "orzo", "pita", "naan", "bagel",
        "toast", "pancake", "waffle",
    ]

    /// Lowercase letters as single-spaced words, padded with spaces: "Pan-Fried Rice" → " pan fried rice ".
    private static func words(_ text: String) -> String {
        " " + String(text.lowercased().map { $0.isLetter ? $0 : " " }).split(separator: " ").joined(separator: " ") + " "
    }

    /// Whether a key starts a word of `text` (from `words`).
    private static func has(_ text: String, _ keys: [String]) -> Bool {
        keys.contains { text.contains(" " + $0) }
    }

    /// An item that can go on a plate: a real serving (not a gallon of sauce) whose calories roughly match its macros
    /// (Nutrislice has some 0-kcal or 10×-off rows), and not a condiment, topping, bar ingredient or dessert.
    static func usable(_ item: FoodItem) -> Bool {
        let name = words(item.name).split(separator: " ").map(String.init)
        let units = words(item.serving).split(separator: " ").map(String.init)
        let atwater = 4 * item.protein + 4 * item.carbs + 9 * item.fat
        return item.kcal >= 5 && item.kcal <= 800
            && abs(item.kcal - atwater) <= max(25, 0.3 * max(item.kcal, atwater))
            && !units.contains(where: bulkUnits.contains)
            && !condiments.contains(name.last ?? "") && !toppings.contains(name.first ?? "")
            && !has(words(item.station ?? ""), barStations)
            && !isDessert(item)
    }

    static func isFried(_ item: FoodItem) -> Bool {
        let name = words(item.name)
        return has(name, friedWords) && !has(name, ["stir fr"])
    }

    static func isDessert(_ item: FoodItem) -> Bool {
        item.category == "dessert" || has(words(item.station ?? ""), ["dessert", "pastr", "bakery", "sweet"])
            || has(words(item.name), dessertWords)
    }

    /// Protein: at least 5 g and a quarter of the calories. Vegetable (or fruit): named as one, not a grain dish, and a
    /// light side. Starch: half the calories from carbs and at least 8 g. Pizza and soup are neither.
    static func role(_ item: FoodItem) -> Role {
        let name = words(item.name)
        let kcal = max(item.kcal, 1)
        if item.category == "pizza" || has(name, ["pizza", "soup", "bisque", "chowder"]) { return .other }
        if item.protein >= 5, 4 * item.protein / kcal >= 0.25 { return .protein }
        if has(name, vegetableWords), !has(name, grainWords), item.kcal <= 120 { return .vegetable }
        if item.carbs >= 8, 4 * item.carbs / kcal >= 0.5 { return .starch }
        return .other
    }

    static func tally(_ item: FoodItem, servings s: Double) -> Tally {
        let macros = Macros(kcal: item.kcal * s, protein: item.protein * s, carbs: item.carbs * s, fat: item.fat * s)
        let role = role(item)
        return Tally(
            macros: macros, saturatedFat: (item.saturatedFat ?? 0) * s, addedSugar: (item.addedSugar ?? 0) * s, fiber: (item.fiber ?? 0) * s,
            fried: isFried(item) ? 1 : 0, desserts: isDessert(item) ? 1 : 0, vegetables: role == .vegetable ? 1 : 0, items: 1,
            proteinFoods: role == .protein ? macros : Macros()
        )
    }

    // MARK: - Scoring

    /// How far a plate is from the target; lower is better and 0 is perfect. Each term is a fraction of its target, weighted:
    /// - protein short of the aim ×2, and below 0.4 g/kg ×2 more; over 125% of the aim ×1 (calories better spent on carbs)
    /// - calories over ×3, under ×0.5 (a little under is fine on a cut; over isn't)
    /// - fat over ×0.5; carbs off either way ×0.25
    /// - lean protein: the protein items getting under 60% of their calories from protein ×1 (chicken breast is ~75%,
    ///   meatloaf ~30%)
    /// - saturated fat and added sugar over 10% of calories ×3; fibre takes off up to 0.2 (at 10 g)
    /// - fried items +0.4 each, desserts +1, no vegetable +0.3, and +0.03 an item so ties go to the simpler plate.
    static func penalty(_ t: Tally, for target: Target) -> Double {
        let m = t.macros
        let protein = max(target.protein, 1), proteinMin = max(target.proteinMin, 1), kcal = max(target.kcal, 1)
        var p = 0.0
        p += 2 * max(0, protein - m.protein) / protein
        p += 2 * max(0, proteinMin - m.protein) / proteinMin
        p += 1 * max(0, m.protein - 1.25 * protein) / protein
        p += 3 * max(0, m.kcal - kcal) / kcal
        p += 0.5 * max(0, kcal - m.kcal) / kcal
        p += 0.5 * max(0, m.fat - target.fat) / max(target.fat, 10)
        p += 0.25 * abs(m.carbs - target.carbs) / max(target.carbs, 30)
        if t.proteinFoods.kcal > 0 {
            p += max(0, 0.6 - 4 * t.proteinFoods.protein / t.proteinFoods.kcal)
        }
        let plateKcal = max(m.kcal, 1)
        p += 3 * max(0, 9 * t.saturatedFat / plateKcal - 0.1)
        p += 3 * max(0, 4 * t.addedSugar / plateKcal - 0.1)
        p -= 0.02 * min(t.fiber, 10)
        p += 0.4 * Double(t.fried) + 1 * Double(t.desserts)
        p += t.vegetables == 0 ? 0.3 : 0
        p += 0.03 * Double(t.items)
        return p
    }

    // MARK: - Search

    /// The best plate on `menu`, or nil when nothing on it has protein. Tries every plate of one protein (1–3 servings),
    /// optionally a second protein, a starch (½–2) and a vegetable (1–2), from the few best candidates of each.
    static func bestPlate(_ menu: [FoodItem], for target: Target) -> Plate? {
        var seen = Set<String>()
        let items = menu.filter { usable($0) && seen.insert($0.name.lowercased()).inserted }
        let kcal = { (item: FoodItem) in max(item.kcal, 1) }
        // Leanest protein first; sandwiches, pizza and the like only when there's no real protein.
        var proteins = items.filter { role($0) == .protein }
        if proteins.isEmpty { proteins = items.filter { role($0) == .other && $0.protein >= 10 } }
        proteins = Array(proteins.sorted { quality($0, $0.protein / kcal($0)) > quality($1, $1.protein / kcal($1)) }.prefix(8))
        let starches = items.filter { role($0) == .starch }
            .sorted { quality($0, ($0.carbs - $0.fat) / kcal($0)) > quality($1, ($1.carbs - $1.fat) / kcal($1)) }.prefix(5)
        let vegetables = items.filter { role($0) == .vegetable }
            .sorted { quality($0, -$0.fat / kcal($0)) > quality($1, -$1.fat / kcal($1)) }.prefix(5)

        /// Nothing, or each item at each serving.
        func options(_ list: some Collection<FoodItem>, _ servings: [Double]) -> [(Portion, Tally)?] {
            var out: [(Portion, Tally)?] = [nil]
            for item in list {
                for s in servings { out.append((Portion(item: item, servings: s), tally(item, servings: s))) }
            }
            return out
        }
        let starchOptions = options(starches, [0.5, 1, 1.5, 2])
        let vegetableOptions = options(vegetables, [1, 2])

        var best: Plate?
        for (i, main) in proteins.enumerated() {
            let seconds = options(proteins.dropFirst(i + 1).prefix(3), [1, 2])
            for s in [1, 1.5, 2, 3] {
                let first = (Portion(item: main, servings: s), tally(main, servings: s))
                for second in seconds {
                    for starch in starchOptions {
                        for vegetable in vegetableOptions {
                            var total = first.1
                            if let second { total = total + second.1 }
                            if let starch { total = total + starch.1 }
                            if let vegetable { total = total + vegetable.1 }
                            let p = penalty(total, for: target)
                            if p < best?.penalty ?? .infinity {
                                let portions = [first.0, second?.0, starch?.0, vegetable?.0].compactMap { $0 }
                                best = Plate(portions: portions, tally: total, penalty: p)
                            }
                        }
                    }
                }
            }
        }
        return best
    }

    /// Orders candidates by `base`, moving fried ones down the list.
    private static func quality(_ item: FoodItem, _ base: Double) -> Double {
        base - (isFried(item) ? 0.3 : 0)
    }

    // MARK: - Explaining

    /// One line on how the plate fits, e.g. "48 g protein, fits your 650 kcal · vegetables".
    static func reason(_ plate: Plate, for target: Target) -> String {
        let m = plate.tally.macros
        let protein = Int(m.protein.rounded()), kcal = Int(m.kcal.rounded()), goal = Int(target.kcal)
        var line = m.protein < target.proteinMin ? "Only \(protein) g protein" : "\(protein) g protein"
        if abs(m.kcal - target.kcal) <= 0.1 * target.kcal {
            line += ", fits your \(goal.formatted()) kcal"
        } else if m.kcal > target.kcal {
            line += ", \((kcal - goal).formatted()) kcal over"
        } else {
            line += ", \(kcal.formatted()) of \(goal.formatted()) kcal"
        }
        var notes: [String] = []
        if plate.tally.vegetables > 0 { notes.append("vegetables") }
        if plate.tally.fried > 0 { notes.append("fried") }
        return ([line] + notes).joined(separator: " · ")
    }
}
