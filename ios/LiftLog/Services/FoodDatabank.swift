import Foundation
import Supabase

/// Shared foods table (USDA seed + Open Food Facts cache + user foods) in Supabase.
enum FoodDatabank {
    struct Row: Codable {
        var id: UUID
        var name: String
        var brand: String?
        var serving: String
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double

        var item: FoodItem {
            FoodItem(id: id.uuidString, name: name, brand: brand, serving: serving, kcal: kcal, protein: protein, carbs: carbs, fat: fat)
        }
    }

    struct NewFood: Encodable {
        var source: String
        var source_id: String?
        var barcode: String?
        var name: String
        var brand: String?
        var serving: String
        var serving_g: Double?
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var created_by: UUID
    }

    private static let columns = "id, name, brand, serving, kcal, protein, carbs, fat"

    static func search(_ query: String, client: SupabaseClient) async throws -> [FoodItem] {
        struct Params: Encodable {
            let q: String
            let max_rows: Int
        }
        let rows: [Row] = try await client.rpc("search_foods", params: Params(q: query, max_rows: 60)).execute().value
        return rows.map(\.item)
    }

    static func normalize(_ barcode: String) -> String? {
        let digits = String(barcode.filter(\.isNumber).drop(while: { $0 == "0" }))
        return (6...14).contains(digits.count) ? digits : nil
    }

    /// Looks up the databank first, then Open Food Facts (saving the hit as the user's own food, visible only to them).
    static func lookup(barcode raw: String, client: SupabaseClient, userId: UUID) async throws -> FoodItem? {
        guard let code = normalize(raw) else { return nil }
        let local: [Row] = try await client.from("foods").select(columns).eq("barcode", value: code).limit(1).execute().value
        if let hit = local.first { return hit.item }
        guard let off = try await openFoodFacts(code, userId: userId) else { return nil }
        let saved: Row = try await client.from("foods").insert(off).select(columns).single().execute().value
        return saved.item
    }

    static func create(_ food: NewFood, client: SupabaseClient) async throws -> FoodItem {
        let saved: Row = try await client.from("foods").insert(food).select(columns).single().execute().value
        return saved.item
    }

    private struct OffResponse: Decodable {
        struct Product: Decodable {
            let product_name: String?
            let brands: String?
            let serving_size: String?
            let serving_quantity: FlexibleDouble?
            let nutriments: [String: FlexibleDouble]?
        }
        let product: Product?
    }

    /// OFF sends numbers as either JSON numbers or strings.
    struct FlexibleDouble: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            value = (try? c.decode(Double.self)) ?? (try? c.decode(String.self)).flatMap(Double.init)
        }
    }

    private static func openFoodFacts(_ code: String, userId: UUID) async throws -> NewFood? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,serving_size,serving_quantity,nutriments") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("LiftLog/1.0 (https://github.com/aarokiya/liftlog-app)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let p = try? JSONDecoder().decode(OffResponse.self, from: data).product,
              let name = p.product_name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let n = p.nutriments ?? [:]
        let grams = (p.serving_quantity?.value).flatMap { $0 > 0 ? $0 : nil }
        func value(_ key: String) -> Double {
            if grams != nil, let s = n["\(key)_serving"]?.value { return s }
            let per100 = n["\(key)_100g"]?.value ?? 0
            return per100 * (grams ?? 100) / 100
        }
        func r1(_ x: Double) -> Double { (max(0, x) * 10).rounded() / 10 }
        return NewFood(
            source: "user", source_id: nil, barcode: code, name: String(name.prefix(200)),
            brand: p.brands?.split(separator: ",").first.map { String($0.trimmingCharacters(in: .whitespaces).prefix(120)) },
            serving: String((grams != nil ? (p.serving_size ?? "\(Int(grams ?? 100)) g") : "100 g").prefix(120)), serving_g: grams,
            kcal: r1(value("energy-kcal")), protein: r1(value("proteins")), carbs: r1(value("carbohydrates")), fat: r1(value("fat")),
            created_by: userId
        )
    }
}
