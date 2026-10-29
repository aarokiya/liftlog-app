import Foundation

struct FoodItem: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    var brand: String?
    var station: String?
    let serving: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct FoodGroup: Identifiable {
    let id: String
    let items: [FoodItem]

    /// Groups by station (or brand), keeping first-seen order.
    static func by(_ key: (FoodItem) -> String?, _ items: [FoodItem]) -> [FoodGroup] {
        var order: [String] = []
        var groups: [String: [FoodItem]] = [:]
        for item in items {
            let k = key(item) ?? "Other"
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(item)
        }
        return order.map { FoodGroup(id: $0, items: groups[$0] ?? []) }
    }
}

enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    static func current(_ date: Date = .now) -> Meal {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 11 ? .breakfast : hour < 16 ? .lunch : .dinner
    }
}

struct SnackBrand: Decodable, Hashable {
    let name: String
    /// Databank search that finds this brand's products.
    let q: String
    /// Text a product's name or brand must contain; defaults to `name`.
    var match: String?

    /// Search results that are really this brand (the search also matches lookalikes, e.g. "layer" for Lay's);
    /// all of them if none match.
    func filter(_ items: [FoodItem]) -> [FoodItem] {
        let key = Self.squash(match ?? name)
        let hits = items.filter { Self.squash("\($0.name) \($0.brand ?? "")").contains(key) }
        return hits.isEmpty ? items : hits
    }

    static func squash(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

extension Array where Element == FoodItem {
    /// Drops rows that look identical: same name, brand, serving and calories.
    func uniqued() -> [FoodItem] {
        var seen = Set<String>()
        return filter { seen.insert("\($0.name)|\($0.brand ?? "")|\($0.serving)|\(Int($0.kcal.rounded()))".lowercased()).inserted }
    }
}

struct SnackGroup: Decodable, Identifiable {
    let name: String
    let brands: [SnackBrand]
    var id: String { name }
}

/// Bundled restaurant menus and dining-hall staples, plus snack brands that search the databank (shared/food).
enum FoodLibrary {
    private struct File: Decodable { let items: [FoodItem] }

    /// Official chain menus (restaurants.json) replace the older USDA items (fast-food.json) for the same chain.
    static let fastFood: [FoodItem] = {
        let official = load("restaurants")
        let chains = Set(official.compactMap(\.brand))
        return official + load("fast-food").filter { !chains.contains($0.brand ?? "") }
    }()
    static let staples = load("dining-staples")

    /// Restaurant names A–Z, with USDA's unbranded fast food last.
    static let restaurants: [String] = Set(fastFood.compactMap(\.brand)).sorted {
        ($0 == "Generic" ? 1 : 0, $0.lowercased()) < ($1 == "Generic" ? 1 : 0, $1.lowercased())
    }

    static let snackGroups: [SnackGroup] = {
        struct Snacks: Decodable { let groups: [SnackGroup] }
        guard let url = Bundle.main.url(forResource: "snack-brands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(Snacks.self, from: data) else { return [] }
        return file.groups
    }()

    private static func load(_ name: String) -> [FoodItem] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.items
    }
}

struct DiningHall: Identifiable, Hashable {
    let id: String
    let name: String
    let meals: [String]
}

/// Georgia Tech Dining menus from Nutrislice (techdining.nutrislice.com).
enum DiningService {
    static let halls = [
        DiningHall(id: "north-ave-dining-hall", name: "North Ave Dining Hall", meals: ["breakfast", "lunch", "dinner", "overnight"]),
        DiningHall(id: "west-village", name: "West Village", meals: ["breakfast", "lunch", "dinner"]),
        DiningHall(id: "brittain", name: "Brittain Dining Hall", meals: ["breakfast", "lunch", "dinner"]),
    ]

    private struct Week: Decodable { let days: [Day] }
    private struct Day: Decodable {
        let date: String
        let menu_items: [Item]
    }
    private struct Item: Decodable {
        let text: String?
        let is_station_header: Bool?
        let food: Food?
    }
    private struct Food: Decodable {
        let id: Int
        let name: String
        let rounded_nutrition_info: Nutrition?
        let serving_size_info: Serving?
    }
    private struct Nutrition: Decodable {
        let calories: Double?
        let g_protein: Double?
        let g_carbs: Double?
        let g_fat: Double?
    }
    private struct Serving: Decodable {
        let serving_size_amount: String?
        let serving_size_unit: String?
    }

    static func menu(hall: String, meal: String, date: Date = .now) async throws -> [FoodItem] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2026, m = c.month ?? 1, d = c.day ?? 1
        let path = String(format: "%@/menu-type/%@/%04d/%02d/%02d/", hall, meal, y, m, d)
        guard let url = URL(string: "https://techdining.api.nutrislice.com/menu/api/weeks/school/\(path)?format=json") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let week = try JSONDecoder().decode(Week.self, from: data)
        let key = String(format: "%04d-%02d-%02d", y, m, d)
        guard let day = week.days.first(where: { $0.date == key }) else { return [] }
        var station = "Menu"
        var seen = Set<String>()
        var items: [FoodItem] = []
        for item in day.menu_items {
            if item.is_station_header == true {
                station = item.text ?? station
                continue
            }
            guard let food = item.food, seen.insert("\(station)|\(food.name)").inserted else { continue }
            let n = food.rounded_nutrition_info
            let serving = [food.serving_size_info?.serving_size_amount, food.serving_size_info?.serving_size_unit]
                .compactMap { $0 }.joined(separator: " ")
            items.append(FoodItem(
                id: "ns-\(food.id)-\(station)", name: food.name, station: station,
                serving: serving.isEmpty ? "1 serving" : serving,
                kcal: n?.calories ?? 0, protein: n?.g_protein ?? 0, carbs: n?.g_carbs ?? 0, fat: n?.g_fat ?? 0
            ))
        }
        return items
    }
}
