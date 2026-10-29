import Foundation

/// Daily calorie and macro targets that adapt to what was eaten, mirrored from web/src/lib/aesthetics/energy.ts.
/// Both port the same reference formulas literally and test against shared/fixtures/energy-cases.json.
public enum Energy {
    static let kcalPerKg = 7700.0
    static let activity = 1.55
    static let lbPerKg = 2.20462

    public struct Targets: Equatable, Sendable {
        public let kcal: Int
        public let protein: Int
        public let carbs: Int
        public let fat: Int

        public init(kcal: Int, protein: Int, carbs: Int, fat: Int) {
            self.kcal = kcal
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
        }
    }

    public struct Base: Equatable, Sendable {
        public let targets: Targets
        /// Calories never go below this: BMR, and at least 1500 for men or 1200 for women.
        public let kcalFloor: Int
        /// Fat never goes below 0.5 g per kg of body weight.
        public let fatFloor: Int

        public init(targets: Targets, kcalFloor: Int, fatFloor: Int) {
            self.targets = targets
            self.kcalFloor = kcalFloor
            self.fatFloor = fatFloor
        }
    }

    /// What was eaten on one day: calories and grams of fat.
    public struct Intake: Equatable, Sendable {
        public var kcal: Double
        public var fat: Double

        public init(kcal: Double, fat: Double) {
            self.kcal = kcal
            self.fat = fat
        }
    }

    /// Positive values only, where this and JS `Math.round` agree.
    private static func rnd(_ x: Double) -> Int { Int(x.rounded()) }

    private static func round10(_ x: Double) -> Int { rnd(x / 10) * 10 }

    /// Katch-McArdle basal metabolic rate in kcal per day.
    public static func bmr(leanMassKg: Double) -> Double {
        370 + 21.6 * leanMassKg
    }

    /// Maintenance estimate: BMR × 1.55, moderately active (lifting several times a week).
    public static func formulaMaintenance(leanMassKg: Double) -> Int {
        rnd(bmr(leanMassKg: leanMassKg) * activity)
    }

    /// Maintenance from the logs: mean intake on complete days minus the weight trend (7700 kcal per kg), blended with
    /// `formula` by how many days were logged (fully learned at 28). Uses the 28 days before `today`; a day counts when
    /// it's at least 40% of `formula`. Needs 10 such days and 4 weigh-ins spanning 14+ days, else returns `formula`.
    /// The observed value is clamped to 75–125% of `formula`.
    /// intake: kcal per day number (LocalDate.dayNumber); weights in kg, sorted by day.
    public static func learnedMaintenance(formula: Int, intake: [Int: Double], weightsKg: [(day: Int, kg: Double)], today: Int) -> Int {
        let f = Double(formula)
        let complete = intake.keys.sorted().filter { today - 28 <= $0 && $0 <= today - 1 }.compactMap { intake[$0] }.filter { $0 >= 0.4 * f }
        let points = weightsKg.filter { today - 28 <= $0.day && $0.day <= today }
        guard complete.count >= 10, points.count >= 4 else { return formula }
        let days = points.map(\.day)
        guard let first = days.min(), let last = days.max(), last - first >= 14 else { return formula }
        let n = Double(points.count)
        let meanDay = Double(days.reduce(0, +)) / n
        let meanKg = points.reduce(0.0) { $0 + $1.kg } / n
        let sxx = days.reduce(0.0) { $0 + (Double($1) - meanDay) * (Double($1) - meanDay) }
        let slope = points.reduce(0.0) { $0 + (Double($1.day) - meanDay) * ($1.kg - meanKg) } / sxx
        var observed = complete.reduce(0.0, +) / Double(complete.count) - slope * kcalPerKg
        observed = min(max(observed, 0.75 * f), 1.25 * f)
        let w = min(1, Double(complete.count - 7) / 21)
        return rnd(f + w * (observed - f))
    }

    /// The plan's daily targets before carryover: maintenance minus (cuts) or plus (lean bulk) the middle of the weekly
    /// rate at 7700 kcal per kg, to the nearest 10. Protein is the plan's; fat is 25% of calories, at least 0.5 g per kg
    /// of body weight; carbs fill the rest. `bodyWeight` and the plan's weights are in `unit`.
    public static func base(plan: Aesthetics.BodyPlan, bodyWeight: Double, unit: WeightUnit, maintenance: Int, sex: Advanced.Sex) -> Base {
        func kg(_ v: Double) -> Double { unit == .kg ? v : v / lbPerKg }
        let kcalFloor = max(rnd(bmr(leanMassKg: kg(plan.leanMass))), sex == .female ? 1200 : 1500)
        let midKg = kg((plan.weeklyLow + plan.weeklyHigh) / 2)
        let delta = midKg * kcalPerKg / 7 * (plan.phase == .leanBulk ? 1 : -1)
        let kcal = max(kcalFloor, round10(Double(maintenance) + delta))
        let protein = plan.proteinG
        let fatFloor = rnd(0.5 * kg(bodyWeight))
        let fat = max(fatFloor, rnd(0.25 * Double(kcal) / 9))
        let carbs = rnd(max(0, Double(kcal - 4 * protein - 9 * fat) / 4))
        return Base(targets: Targets(kcal: kcal, protein: protein, carbs: carbs, fat: fat), kcalFloor: kcalFloor, fatFloor: fatFloor)
    }

    /// Targets for each day from `from` through `through`. A day's miss (intake minus its target) is paid back evenly
    /// over the next 3 days, capped at ±15% of the base calories and ±25% of the base fat, and never below the floors.
    /// Only complete days count (intake at least 50% of that day's target). Protein stays fixed; carbs fill the rest.
    public static func daily(base: Base, intake: [Int: Intake], from: Int, through: Int) -> [Int: Targets] {
        let t = base.targets
        let kcalBase = Double(t.kcal), fatBase = Double(t.fat)
        var out: [Int: Targets] = [:]
        var devKcal: [Int: Double] = [:], devFat: [Int: Double] = [:]
        for d in stride(from: from, through: through, by: 1) {
            var adjKcal = -((devKcal[d - 1] ?? 0) + (devKcal[d - 2] ?? 0) + (devKcal[d - 3] ?? 0)) / 3
            var adjFat = -((devFat[d - 1] ?? 0) + (devFat[d - 2] ?? 0) + (devFat[d - 3] ?? 0)) / 3
            adjKcal = min(max(adjKcal, -0.15 * kcalBase), 0.15 * kcalBase)
            adjFat = min(max(adjFat, -0.25 * fatBase), 0.25 * fatBase)
            let kcal = max(base.kcalFloor, round10(kcalBase + adjKcal))
            let fat = max(base.fatFloor, rnd(fatBase + adjFat))
            let carbs = rnd(max(0, Double(kcal - 4 * t.protein - 9 * fat) / 4))
            out[d] = Targets(kcal: kcal, protein: t.protein, carbs: carbs, fat: fat)
            if let i = intake[d], i.kcal >= 0.5 * Double(kcal) {
                devKcal[d] = i.kcal - Double(kcal)
                devFat[d] = i.fat - Double(fat)
            }
        }
        return out
    }
}
