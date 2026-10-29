import Foundation

public enum OneRepMaxFormula: String, Codable, CaseIterable, Sendable {
    case epley
    case brzycki
    case lombardi
}

public enum OneRepMax {
    /// Sets above this rep count are too inaccurate to estimate a 1RM from.
    public static let maxReps = 12

    public static func estimate(weight: Double, reps: Int, formula: OneRepMaxFormula = .epley) -> Double? {
        guard weight > 0, reps >= 1, reps <= maxReps else { return nil }
        if reps == 1 { return weight }
        let r = Double(reps)
        switch formula {
        case .epley: return weight * (1 + r / 30)
        case .brzycki: return weight * 36 / (37 - r)
        case .lombardi: return weight * pow(r, 0.10)
        }
    }

    public struct SessionBest: Equatable, Sendable {
        public let sessionId: String
        public let value: Double
    }

    /// Best estimated 1RM per session, in first-seen session order.
    public static func bestPerSession(_ sets: [LiftSet], unit: WeightUnit, formula: OneRepMaxFormula = .epley) -> [SessionBest] {
        var order: [String] = []
        var best: [String: Double] = [:]
        for set in sets where set.type.countsTowardStats {
            guard let e = estimate(weight: set.weight(in: unit), reps: set.reps, formula: formula) else { continue }
            if best[set.sessionId] == nil { order.append(set.sessionId) }
            best[set.sessionId] = max(best[set.sessionId] ?? 0, e)
        }
        return order.map { SessionBest(sessionId: $0, value: best[$0]!) }
    }
}
