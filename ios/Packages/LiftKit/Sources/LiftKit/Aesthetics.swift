import Foundation

/// Body-composition helpers mirrored from web/src/lib/aesthetics.
public enum Aesthetics {
    /// U.S. Navy circumference method (men), lengths in cm.
    public static func navyBodyFatMale(heightCm: Double, waistCm: Double, neckCm: Double) -> Double? {
        guard heightCm > 0, waistCm > neckCm else { return nil }
        let pct = 495 / (1.0324 - 0.19077 * log10(waistCm - neckCm) + 0.15456 * log10(heightCm)) - 450
        return (pct * 10).rounded() / 10
    }

    /// Relative fat mass (men): needs only height and waist, used when there's no neck measurement.
    public static func rfmMale(heightCm: Double, waistCm: Double) -> Double? {
        guard heightCm > 0, waistCm > 0 else { return nil }
        return ((64 - 20 * heightCm / waistCm) * 10).rounded() / 10
    }

    /// U.S. Navy circumference method (women), lengths in cm; needs hips as well as waist and neck.
    public static func navyBodyFatFemale(heightCm: Double, waistCm: Double, hipsCm: Double, neckCm: Double) -> Double? {
        guard heightCm > 0, waistCm + hipsCm > neckCm else { return nil }
        let pct = 495 / (1.29579 - 0.35004 * log10(waistCm + hipsCm - neckCm) + 0.22100 * log10(heightCm)) - 450
        return (pct * 10).rounded() / 10
    }

    /// Relative fat mass (women).
    public static func rfmFemale(heightCm: Double, waistCm: Double) -> Double? {
        guard heightCm > 0, waistCm > 0 else { return nil }
        return ((76 - 20 * heightCm / waistCm) * 10).rounded() / 10
    }

    /// Tape estimate: the Navy formula when its measurements are there (neck, plus hips for women), else RFM.
    public static func bodyFatEstimate(sex: Advanced.Sex, heightCm: Double, waistCm: Double, neckCm: Double?, hipsCm: Double?) -> Double? {
        switch sex {
        case .male:
            neckCm.flatMap { navyBodyFatMale(heightCm: heightCm, waistCm: waistCm, neckCm: $0) } ?? rfmMale(heightCm: heightCm, waistCm: waistCm)
        case .female:
            neckCm.flatMap { neck in hipsCm.flatMap { navyBodyFatFemale(heightCm: heightCm, waistCm: waistCm, hipsCm: $0, neckCm: neck) } }
                ?? rfmFemale(heightCm: heightCm, waistCm: waistCm)
        }
    }

    /// Default goal body fat: 12% for men, 22% for women (women carry about 10 points more essential fat).
    public static func defaultGoalPct(_ sex: Advanced.Sex) -> Double { sex == .female ? 22 : 12 }

    public static func waistToHip(waistCm: Double, hipsCm: Double) -> Double? {
        hipsCm > 0 ? (waistCm / hipsCm * 1000).rounded() / 1000 : nil
    }

    /// Shoulder circumference at the golden ratio (1.618 × waist), the classic V-taper target.
    public static func shoulderTarget(waistCm: Double) -> Double {
        (waistCm * 1.618 * 10).rounded() / 10
    }

    public static func waistToHeight(waistCm: Double, heightCm: Double) -> Double? {
        heightCm > 0 ? (waistCm / heightCm * 1000).rounded() / 1000 : nil
    }

    public enum WaistBand: String, Sendable {
        case lean, healthy, elevated, high
    }

    public static func band(_ ratio: Double) -> WaistBand {
        switch ratio {
        case ..<0.43: .lean
        case ..<0.5: .healthy
        case ..<0.6: .elevated
        default: .high
        }
    }

    public enum Phase: String, Sendable {
        case cut, slowCut = "slow_cut", leanBulk = "lean_bulk"

        public var label: String {
            switch self {
            case .cut: "Cut"
            case .slowCut: "Slow cut"
            case .leanBulk: "Lean bulk"
            }
        }

        /// Weekly body-weight change as a fraction of body weight (loss for cuts, gain for lean bulk).
        var rates: (low: Double, high: Double) {
            switch self {
            case .cut: (0.005, 0.01)
            case .slowCut: (0.0025, 0.005)
            case .leanBulk: (0.001, 0.0025)
            }
        }
    }

    public struct BodyPlan: Equatable, Sendable {
        public let phase: Phase
        public let leanMass: Double
        public let goalWeight: Double
        /// First target: ~7% of body weight off (never past the goal), then reassess.
        public let checkpoint: Double
        /// Weight to lose to reach the checkpoint, not the goal.
        public let toLose: Double
        public let weeklyLow: Double
        public let weeklyHigh: Double
        /// Weeks to the checkpoint at the middle of the weekly range.
        public let weeks: Int?
        public let proteinG: Int
    }

    /// Men: cut at 20%+ body fat, slow cut at 15–20%, lean bulk below 15%. Women: the same bands 10 points higher.
    public static func phase(bodyFatPct: Double, sex: Advanced.Sex = .male) -> Phase {
        let shift = sex == .female ? 10.0 : 0
        return bodyFatPct >= 20 + shift ? .cut : bodyFatPct >= 15 + shift ? .slowCut : .leanBulk
    }

    /// Goal weight keeps current lean mass at `goalPct` body fat; protein is 2.2 g per kg of goal weight.
    /// `startWeight` is the body weight when `bodyFatPct` was measured (defaults to `bodyWeight`). Lean mass, the goal
    /// and the checkpoint come from it, so they hold still while the weight to lose counts down.
    public static func bodyPlan(
        bodyWeight: Double, unit: WeightUnit, bodyFatPct: Double, goalPct: Double? = nil, startWeight: Double? = nil, sex: Advanced.Sex = .male
    ) -> BodyPlan {
        let goalPct = goalPct ?? defaultGoalPct(sex)
        let p = phase(bodyFatPct: bodyFatPct, sex: sex)
        let (lo, hi) = p.rates
        let start = startWeight ?? bodyWeight
        let lean = start * (1 - bodyFatPct / 100)
        let goal = lean / (1 - goalPct / 100)
        let checkpoint = max(goal, start * 0.93)
        let toLose = max(0, bodyWeight - checkpoint)
        let goalKg = unit == .kg ? goal : goal / 2.20462
        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        return BodyPlan(
            phase: p, leanMass: r1(lean), goalWeight: r1(goal), checkpoint: r1(checkpoint), toLose: r1(toLose),
            weeklyLow: r1(bodyWeight * lo), weeklyHigh: r1(bodyWeight * hi),
            weeks: p == .leanBulk || toLose == 0 ? nil : Int((toLose / (bodyWeight * (lo + hi) / 2)).rounded(.up)),
            proteinG: Int((goalKg * 2.2).rounded())
        )
    }

    /// Weekly hard-set targets; priority muscles build the V-taper.
    public static let targets: [(muscle: String, min: Int, max: Int, priority: Bool)] = [
        ("side_delts", 12, 20, true), ("back", 12, 20, true), ("chest", 10, 16, true), ("rear_delts", 8, 14, true),
        ("core", 6, 12, true), ("quads", 8, 14, false), ("hamstrings", 6, 12, false), ("glutes", 4, 10, false),
        ("calves", 6, 12, false), ("biceps", 6, 14, false), ("triceps", 6, 14, false),
    ]
}
