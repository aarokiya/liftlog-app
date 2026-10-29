import Foundation

public enum Volume {
    /// Sum of weight × reps over non-warm-up sets.
    public static func load(_ sets: [LiftSet], unit: WeightUnit) -> Double {
        sets.lazy.filter { $0.type.countsTowardStats }
            .reduce(0) { $0 + $1.weight(in: unit) * Double($1.reps) }
    }
}

public enum PersonalRecords {
    public static let repRange = 1...20

    /// Heaviest weight lifted for each exact rep count (1–20), excluding warm-ups.
    public static func repMaxes(_ sets: [LiftSet], unit: WeightUnit) -> [Int: Double] {
        var out: [Int: Double] = [:]
        for set in sets where set.type.countsTowardStats && repRange.contains(set.reps) {
            out[set.reps] = max(out[set.reps] ?? 0, set.weight(in: unit))
        }
        return out
    }
}

public struct ExerciseMuscles: Codable, Hashable, Sendable {
    public var primary: String
    public var secondary: [String]

    public init(primary: String, secondary: [String] = []) {
        self.primary = primary
        self.secondary = secondary
    }
}

public enum MuscleSets {
    public static let secondaryWeight = 0.5

    /// Hard sets per muscle: primary muscle counts 1, each secondary 0.5. Warm-ups and unknown exercises are skipped.
    public static func count(_ sets: [LiftSet], exercises: [String: ExerciseMuscles]) -> [String: Double] {
        var out: [String: Double] = [:]
        for set in sets where set.type.countsTowardStats {
            guard let muscles = exercises[set.exerciseId] else { continue }
            out[muscles.primary, default: 0] += 1
            for m in muscles.secondary { out[m, default: 0] += secondaryWeight }
        }
        return out
    }
}

public enum PlateCalculator {
    public struct Result: Equatable, Sendable {
        public let perSide: [Double]
        /// Total weight that could not be loaded with the available plates.
        public let remainder: Double
    }

    public static func plates(target: Double, bar: Double, available: [Double]) -> Result {
        var side = (target - bar) / 2
        guard side >= 0 else { return Result(perSide: [], remainder: target - bar) }
        var plates: [Double] = []
        for plate in available.sorted(by: >) where plate > 0 {
            while side >= plate - 1e-9 {
                plates.append(plate)
                side -= plate
            }
        }
        return Result(perSide: plates, remainder: (side * 2 * 1e6).rounded() / 1e6)
    }
}

public enum Trend {
    public struct Line: Equatable, Sendable {
        public let slope: Double
        public let intercept: Double
    }

    /// Ordinary least squares fit. Returns nil for fewer than two points or no x variance.
    public static func linearRegression(_ points: [(x: Double, y: Double)]) -> Line? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n
        let my = points.reduce(0) { $0 + $1.y } / n
        let sxx = points.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) }
        guard sxx > 0 else { return nil }
        let sxy = points.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) }
        let slope = sxy / sxx
        return Line(slope: slope, intercept: my - slope * mx)
    }
}
