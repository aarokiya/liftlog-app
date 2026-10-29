import Foundation

enum Muscle {
    static let all: [(id: String, label: String)] = [
        ("chest", "Chest"),
        ("back", "Back"),
        ("traps", "Traps"),
        ("front_delts", "Front delts"),
        ("side_delts", "Side delts"),
        ("rear_delts", "Rear delts"),
        ("biceps", "Biceps"),
        ("triceps", "Triceps"),
        ("forearms", "Forearms"),
        ("core", "Core"),
        ("quads", "Quads"),
        ("hamstrings", "Hamstrings"),
        ("glutes", "Glutes"),
        ("calves", "Calves"),
        ("adductors", "Adductors"),
        ("abductors", "Abductors"),
        ("hip_flexors", "Hip flexors"),
    ]

    static func label(_ id: String) -> String {
        all.first { $0.id == id }?.label ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
