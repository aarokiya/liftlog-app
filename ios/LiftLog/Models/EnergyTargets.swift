import Foundation
import LiftKit

/// The Food screen's daily calorie and macro targets: the body plan's base targets around maintenance (learned from the
/// logs once there are enough), adjusted each day for the last 3 days' misses. Days are `LocalDate.dayNumber`s.
struct EnergyTargets {
    let maintenance: Int
    /// Maintenance came from intake and weigh-ins rather than the lean-mass formula alone.
    let learned: Bool
    let base: Energy.Base
    let days: [Int: Energy.Targets]

    subscript(day: Date) -> Energy.Targets? { days[LocalDate(date: day).dayNumber] }

    /// 33 days before today: enough history for maintenance and carryover.
    static func historyStart(_ now: Date = .now) -> Date? {
        Calendar.current.date(byAdding: .day, value: -33, to: Calendar.current.startOfDay(for: now))
    }

    /// nil without a plan: needs the sex setting, a logged body-fat % and a body weight. `metrics` are newest first, as
    /// the Food screen queries them. Intake is food logged here plus what other apps saved to Health (`health`, keyed by
    /// start of day, loaded from `start` on). Targets run from `start` through today. Maintenance looks at the 28 days
    /// before today, so `start` should reach at least that far back.
    init?(metrics: [BodyMetric], logs: [FoodLog], health: [Date: HealthService.Nutrition], sex: Advanced.Sex?,
          unit: WeightUnit, from start: Date, now: Date = .now) {
        let live = metrics.filter { $0.deletedAt == nil }
        guard let sex, let bf = live.first(where: { $0.bodyFatPct != nil })?.bodyFatPct,
              let entry = live.first(where: { $0.bodyWeight != nil }), let bw = entry.bodyWeight else { return nil }
        let bodyWeight = entry.unit.convert(bw, to: unit)
        let plan = Aesthetics.bodyPlan(bodyWeight: bodyWeight, unit: unit, bodyFatPct: bf, startWeight: live.planStartWeight(in: unit), sex: sex)

        let from = LocalDate(date: start).dayNumber
        let today = LocalDate(date: now).dayNumber
        var intake: [Int: Energy.Intake] = [:]
        for log in logs where log.deletedAt == nil && log.eatenAt >= start {
            let day = LocalDate(date: log.eatenAt).dayNumber
            intake[day, default: Energy.Intake(kcal: 0, fat: 0)].kcal += log.kcal * log.servings
            intake[day, default: Energy.Intake(kcal: 0, fat: 0)].fat += log.fat * log.servings
        }
        for (date, nutrition) in health {
            let day = LocalDate(date: date).dayNumber
            intake[day, default: Energy.Intake(kcal: 0, fat: 0)].kcal += nutrition.kcal
            intake[day, default: Energy.Intake(kcal: 0, fat: 0)].fat += nutrition.fat
        }
        let weights = live.filter { $0.bodyWeight != nil }.sorted { $0.measuredAt < $1.measuredAt }
            .map { (day: LocalDate(date: $0.measuredAt).dayNumber, kg: $0.unit.convert($0.bodyWeight ?? 0, to: .kg)) }

        let formula = Energy.formulaMaintenance(leanMassKg: unit.convert(plan.leanMass, to: .kg))
        maintenance = Energy.learnedMaintenance(formula: formula, intake: intake.mapValues(\.kcal), weightsKg: weights, today: today)
        learned = maintenance != formula
        base = Energy.base(plan: plan, bodyWeight: bodyWeight, unit: unit, maintenance: maintenance, sex: sex)
        days = Energy.daily(base: base, intake: intake, from: min(from, today), through: today)
    }
}
