import SwiftUI

/// Georgia Tech: the dining halls' live menus, every other GT Dining location and restaurants near campus.
struct CampusView: View {
    @State private var search = ""
    @State private var picked: FoodItem?

    private var areas: [String] {
        var seen = Set<String>()
        return FoodLibrary.campus.map(\.area).filter { seen.insert($0).inserted }
    }

    /// The place a menu item is logged under: the first one serving that brand, on campus before nearby.
    private static let placeByMenu: [String: CampusPlace] = {
        var map: [String: CampusPlace] = [:]
        for place in FoodLibrary.campus {
            if let menu = place.menu, map[menu] == nil { map[menu] = place }
        }
        return map
    }()

    private static let menuItems = placeByMenu.keys.sorted().flatMap(FoodLibrary.menu)

    /// Logged as dining food on campus and outside food off it.
    private var pickedSource: String {
        picked?.brand.flatMap { Self.placeByMenu[$0] }?.onCampus == false ? "outside" : "dining"
    }

    /// Every word of the search appears somewhere in `text`, in any order ("tin drum chicken").
    private func matches(_ text: String) -> Bool {
        search.split(separator: " ").allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    private var matchingPlaces: [CampusPlace] {
        FoodLibrary.campus.filter { matches("\($0.name) \($0.kind ?? "")") }
    }

    private var matchingItems: [FoodItem] {
        Self.menuItems.filter { matches("\($0.brand ?? "") \($0.name)") }
    }

    var body: some View {
        List {
            if search.isEmpty {
                ForEach(areas, id: \.self) { area in
                    Section {
                        if area == "Dining halls" {
                            NavigationLink { DiningPlanView() } label: { WhatToEatLabel() }
                        }
                        ForEach(FoodLibrary.campus.filter { $0.area == area }) { place in
                            NavigationLink { CampusPlaceView(place: place) } label: { CampusPlaceLabel(place: place) }
                        }
                    } header: {
                        Text(area)
                    } footer: {
                        switch area {
                        case "Food trucks": Text("Trucks rotate on Tech Green; dining.gatech.edu has today's schedule.")
                        case "Community Market": Text("Pop-up vendors on Tech Walkway.")
                        case "Near campus": Text("Off campus, nearest first.")
                        default: EmptyView()
                        }
                    }
                }
            } else {
                if !matchingPlaces.isEmpty {
                    Section("Places") {
                        ForEach(matchingPlaces) { place in
                            NavigationLink { CampusPlaceView(place: place) } label: { CampusPlaceLabel(place: place) }
                        }
                    }
                }
                Section("Menu items") {
                    ForEach(matchingItems.prefix(100)) { item in
                        FoodRow(item: item, showBrand: true) { picked = item }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places and menus")
        .navigationTitle("Georgia Tech")
        .logFoodSheet($picked, source: pickedSource, place: { item in item.brand.flatMap { Self.placeByMenu[$0]?.name } ?? item.brand })
    }
}

/// The dining halls' "What to eat" row.
private struct WhatToEatLabel: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("What to eat")
                Text("The best plate at each hall for \(Meal.current().label.lowercased())").font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "fork.knife").foregroundStyle(.tint)
        }
    }
}

struct CampusPlaceLabel: View {
    let place: CampusPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.name)
            let info = [place.kind, place.detail].compactMap { $0 }.joined(separator: " · ")
            if !info.isEmpty {
                Text(info).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// A dining hall's live menu, a place's menu, or how to log food from a place with none.
struct CampusPlaceView: View {
    let place: CampusPlace

    var body: some View {
        if let id = place.hall, let hall = DiningService.halls.first(where: { $0.id == id }) {
            HallMenuView(hall: hall)
        } else if let menu = place.menu {
            PlaceMenuView(place: place, items: FoodLibrary.menu(menu))
        } else {
            PlaceNoMenuView(place: place)
        }
    }
}

struct PlaceMenuView: View {
    let place: CampusPlace
    let items: [FoodItem]
    @State private var search = ""
    @State private var picked: FoodItem?

    private var shown: [FoodItem] {
        search.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            ForEach(FoodGroup.by({ $0.station ?? "Menu" }, shown)) { group in
                Section(group.id) {
                    ForEach(group.items) { item in FoodRow(item: item) { picked = item } }
                }
            }
            if items.contains(where: { $0.estimated == true }) {
                Section {
                    Text("≈ \(place.name) doesn't publish nutrition, so these are estimated from USDA ingredients and typical portions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search the menu")
        .navigationTitle(place.name)
        .logFoodSheet($picked, source: place.onCampus ? "dining" : "outside", place: { _ in place.name })
    }
}

struct PlaceNoMenuView: View {
    let place: CampusPlace
    @Environment(\.foodPick) private var pick
    @State private var addingCustom = false

    var body: some View {
        List {
            Section {
                Text(place.note ?? "\(place.name) doesn't publish a menu with nutrition. Log it as a custom food, or find a similar dish in Search all foods.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Button { addingCustom = true } label: { Label("Custom food from \(place.name)", systemImage: "square.and.pencil") }
                NavigationLink { FoodSearchView() } label: { Label("Search all foods / scan barcode", systemImage: "magnifyingglass") }
            }
        }
        .navigationTitle(place.name)
        .sheet(isPresented: $addingCustom) { CustomFoodSheet(pick: pick, place: place.name) }
    }
}
