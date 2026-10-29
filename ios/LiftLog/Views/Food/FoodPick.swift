import SwiftUI

/// A food chosen in a picker: the item, its log source ("dining", "outside" or "custom") and where it's from.
typealias FoodPick = (_ item: FoodItem, _ source: String, _ place: String?) -> Void

private struct FoodPickKey: EnvironmentKey {
    static let defaultValue: FoodPick? = nil
}

extension EnvironmentValues {
    /// Set while replacing a logged food: the food pickers hand the tapped item here instead of opening LogFoodSheet.
    var foodPick: FoodPick? {
        get { self[FoodPickKey.self] }
        set { self[FoodPickKey.self] = newValue }
    }
}

extension View {
    /// Opens LogFoodSheet for the food a picker puts in `item`, or hands it to `\.foodPick` when that's set.
    /// `meal` defaults to the current meal when the sheet opens.
    func logFoodSheet(_ item: Binding<FoodItem?>, source: String, place: @escaping (FoodItem) -> String?, meal: Meal? = nil) -> some View {
        modifier(LogFoodPresenter(item: item, source: source, place: place, meal: meal))
    }
}

private struct LogFoodPresenter: ViewModifier {
    @Environment(\.foodPick) private var pick
    @Binding var item: FoodItem?
    let source: String
    let place: (FoodItem) -> String?
    let meal: Meal?

    func body(content: Content) -> some View {
        content
            .sheet(item: pick == nil ? $item : .constant(nil)) { item in
                LogFoodSheet(item: item, source: source, place: place(item), meal: meal ?? .current())
            }
            .onChange(of: item) { _, picked in
                guard let pick, let picked else { return }
                item = nil
                pick(picked, source, place(picked))
            }
    }
}

/// Where food comes from: Georgia Tech's dining and nearby restaurants (campus = gatech only), outside food and the
/// foods databank. Used to log food and to pick a replacement for a logged one.
struct AddFoodLinks: View {
    @AppStorage(Prefs.campus) private var campus = ""

    var body: some View {
        if campus == "gatech" {
            NavigationLink { CampusView() } label: { Label("Georgia Tech", systemImage: "building.columns") }
        }
        NavigationLink { OutsideFoodView() } label: { Label("Outside food", systemImage: "takeoutbag.and.cup.and.straw") }
        NavigationLink { FoodSearchView() } label: { Label("Search all foods / scan barcode", systemImage: "magnifyingglass") }
    }
}
