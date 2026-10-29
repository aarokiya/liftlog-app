import LiftKit
import SwiftUI

/// One day's food and water against that day's targets.
struct DayGoals {
    var kcal = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var water = 0.0
    var targets: Energy.Targets?
    var waterGoal: Double?

    var hasData: Bool { kcal > 0 || protein > 0 || carbs > 0 || fat > 0 || water > 0 }
    var proteinState: Goal? { targets.map { Self.grade(protein, Double($0.protein)) } }
    var kcalState: Goal? { targets.map { Goal.near(kcal, Double($0.kcal)) } }
    var waterState: Goal? { waterGoal.map { Self.grade(water, $0) } }

    /// Green when every goal is hit, red when any is missed, orange otherwise. Protein and water are hit at their goal
    /// and close from 85% of it; calories are hit within 10% of the day's target and close within 20%.
    var overall: Goal? {
        let states = [proteinState, kcalState, waterState].compactMap { $0 }
        guard hasData, !states.isEmpty else { return nil }
        if states.allSatisfy({ $0 == .hit }) { return .hit }
        return states.contains(.missed) ? .missed : .close
    }

    static func grade(_ value: Double, _ target: Double) -> Goal {
        value.rounded() >= target ? .hit : value >= target * 0.85 ? .close : .missed
    }

    /// Totals per day, for the goals calendar and reminders: food logged here plus what other apps saved to Health, water,
    /// and each day's goals. Calorie and macro targets are that day's, after carryover; the water goal uses the body
    /// weight logged by that day and is higher on days with a workout. `logs` and `waterLogs` are live rows, `metrics`
    /// newest first, `healthDays` keyed by start of day.
    static func byDay(_ days: [Date], logs: [FoodLog], waterLogs: [WaterLog], workouts: [Workout], metrics: [BodyMetric],
                      waterUnit: WaterUnit, healthDays: [Date: HealthService.Nutrition], targets: EnergyTargets?) -> [Date: DayGoals] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let first = days.first, let last = days.last, let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [:] }
        var result: [Date: DayGoals] = [:]
        for day in days where day <= today { result[day] = DayGoals() }
        for log in logs where log.eatenAt >= first && log.eatenAt < end {
            let day = calendar.startOfDay(for: log.eatenAt)
            result[day]?.kcal += log.kcal * log.servings
            result[day]?.protein += log.protein * log.servings
            result[day]?.carbs += log.carbs * log.servings
            result[day]?.fat += log.fat * log.servings
        }
        for (day, nutrition) in healthDays {
            result[day]?.kcal += nutrition.kcal
            result[day]?.protein += nutrition.protein
            result[day]?.carbs += nutrition.carbs
            result[day]?.fat += nutrition.fat
        }
        for log in waterLogs where log.drankAt >= first && log.drankAt < end {
            result[calendar.startOfDay(for: log.drankAt)]?.water += log.unit.convert(log.amount, to: waterUnit)
        }
        let trained = Set(workouts.filter { $0.deletedAt == nil && $0.startedAt >= first && $0.startedAt < end }.map { calendar.startOfDay(for: $0.startedAt) })
        let weights = metrics.filter { $0.deletedAt == nil && $0.bodyWeight != nil }
        for (day, var goals) in result {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            if let entry = weights.first(where: { $0.measuredAt < dayEnd }) ?? weights.last, let bw = entry.bodyWeight {
                goals.waterGoal = waterUnit.dailyGoal(bodyWeightKg: entry.unit.convert(bw, to: .kg), trained: trained.contains(day))
            }
            goals.targets = targets?[day]
            goals.water = (goals.water * 10).rounded() / 10
            result[day] = goals
        }
        return result
    }
}

/// Month calendar on the Food screen: each day is green, orange or red by whether protein, calories and water hit
/// that day's goals.
struct GoalCalendar: View {
    /// First day of the month shown. The Food screen loads Health totals for it.
    @Binding var month: Date
    /// The day whose totals show under the grid (a start of day). The Food screen lists that day's foods.
    @Binding var selected: Date
    let logs: [FoodLog]
    let waterLogs: [WaterLog]
    let workouts: [Workout]
    let metrics: [BodyMetric]
    let waterUnit: WaterUnit
    /// What other apps saved to Health, keyed by start of day.
    let healthDays: [Date: HealthService.Nutrition]
    let targets: EnergyTargets?

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var isCurrentMonth: Bool { calendar.isDate(month, equalTo: .now, toGranularity: .month) }

    var body: some View {
        let days = monthDays
        let goals = dayGoals(days.compactMap { $0 })
        VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
                    .disabled(isCurrentMonth)
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.bold()).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day, goals[day])
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }

            if let day = goals[selected] {
                detail(selected, day)
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ day: Date, _ goals: DayGoals?) -> some View {
        let isToday = day == today
        // Today isn't over, so it only turns green once you've hit everything; red waits for the day to end.
        let state = day > today ? nil : isToday && goals?.overall != .hit ? nil : goals?.overall
        return Button {
            selected = day
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(day == selected ? .bold : .regular).monospacedDigit())
                .foregroundStyle(state != nil ? Color.white : day > today ? Color.secondary.opacity(0.5) : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Circle().fill(state?.color ?? .clear).frame(width: 34, height: 34))
                .overlay(Circle().strokeBorder(isToday ? Color.accentColor : day == selected ? Color.secondary : .clear, lineWidth: 2).frame(width: 34, height: 34))
        }
        .buttonStyle(.plain)
        .disabled(day > today)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (state.map { ", \(label($0))" } ?? ""))
    }

    private func detail(_ day: Date, _ goals: DayGoals) -> some View {
        let t = goals.targets
        // Today's calories and macros only turn red once they're over; being under is just the day in progress.
        func state(_ value: Double, _ target: Int) -> Goal? {
            day == today ? Goal.soFar(value, Double(target)) : Goal.near(value, Double(target))
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(day == today ? "Today" : day.formatted(.dateTime.weekday(.wide).month().day())).font(.subheadline.bold())
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    amount(goals.kcal, t?.kcal, "kcal", t.flatMap { state(goals.kcal, $0.kcal) })
                    amount(goals.protein, t?.protein, "g protein", goals.proteinState)
                }
                GridRow {
                    amount(goals.carbs, t?.carbs, "g carbs", t.flatMap { state(goals.carbs, $0.carbs) })
                    amount(goals.fat, t?.fat, "g fat", t.flatMap { state(goals.fat, $0.fat) })
                }
            }
            if let goal = goals.waterGoal {
                value("\(Format.number(goals.water)) / \(Format.number(goal)) \(waterUnit.rawValue) water", goals.waterState)
            }
            if t == nil || goals.waterGoal == nil {
                Text(goals.waterGoal == nil
                     ? "Log your body weight in Settings → Body & aesthetics to get water, calorie and macro goals."
                     : "Set your sex and log a body-fat % in Settings → Body & aesthetics to get calorie and macro goals.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amount(_ value: Double, _ target: Int?, _ unit: String, _ state: Goal?) -> some View {
        self.value(target.map { "\(Int(value.rounded()).formatted()) / \($0.formatted()) \(unit)" } ?? "\(Int(value.rounded()).formatted()) \(unit)", state)
    }

    private func value(_ text: String, _ state: Goal?) -> some View {
        Text(text).font(.caption.bold().monospacedDigit()).foregroundStyle(state?.color ?? .primary)
    }

    private func label(_ goal: Goal) -> String {
        switch goal {
        case .hit: "hit every goal"
        case .close: "close"
        case .missed: "missed"
        }
    }

    private func shiftMonth(_ by: Int) {
        guard let next = calendar.date(byAdding: .month, value: by, to: month), next <= .now else { return }
        month = next
        selected = calendar.isDate(next, equalTo: .now, toGranularity: .month) ? today : next
    }

    /// Weekday initials starting from the locale's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days, with leading blanks so the 1st lands under its weekday.
    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days
    }

    private func dayGoals(_ days: [Date]) -> [Date: DayGoals] {
        DayGoals.byDay(days, logs: logs, waterLogs: waterLogs, workouts: workouts, metrics: metrics, waterUnit: waterUnit,
                       healthDays: healthDays, targets: targets)
    }
}
