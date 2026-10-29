import Foundation

extension HealthService.Nutrition {
    /// Calories and macros eaten on `day`: food logged in LiftLog (times servings) plus what other apps saved to Apple
    /// Health that day. `health` is keyed by start of day, as `HealthService.dailyNutrition` returns it.
    static func eaten(on day: Date, logs: [FoodLog], health: [Date: HealthService.Nutrition]) -> HealthService.Nutrition {
        var total = health[Calendar.current.startOfDay(for: day)] ?? HealthService.Nutrition()
        for log in logs where log.deletedAt == nil && Calendar.current.isDate(log.eatenAt, inSameDayAs: day) {
            total.kcal += log.kcal * log.servings
            total.protein += log.protein * log.servings
            total.carbs += log.carbs * log.servings
            total.fat += log.fat * log.servings
        }
        return total
    }
}
