import Foundation

/// Gym equipment profile from shared/gyms (same file the web dashboard reads).
struct GymProfile: Decodable {
    struct Group: Decodable {
        let pattern: String
        let exercises: [Int]
    }
    let id: String
    let name: String
    let substitution_groups: [Group]
}

enum GymLibrary {
    static let crc: GymProfile? = {
        guard let url = Bundle.main.url(forResource: "gatech-crc", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GymProfile.self, from: data)
    }()

    static func builtInId(_ n: Int) -> UUID? {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))
    }

    /// Other exercises with the same movement pattern, in the CRC's preference order. Most gyms have these too, so it's offered to everyone.
    static func substitutes(for id: UUID, among exercises: [Exercise]) -> [Exercise] {
        guard let group = crc?.substitution_groups.first(where: { $0.exercises.contains { builtInId($0) == id } }) else { return [] }
        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return group.exercises.compactMap { builtInId($0) }.filter { $0 != id }.compactMap { byId[$0] }
    }
}
