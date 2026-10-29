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
    /// Health's step counts by start of day, from 28 days before the month; empty without Health. Shown for the picked
    /// day, but they don't color the calendar.
    let steps: [Date: Double]
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
                Divider()
                summary(selected, day)
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

    private struct Stat: Identifiable {
        let value: String
        let label: String
        let state: Goal?
        /// Read out with the value, e.g. "of 2,450".
        var target: String?
        var id: String { label }
    }

    /// The picked day in one row, each amount green, orange or red against that day's goal, under its date and a
    /// one-line legend for the day colors. Today is still going, so being under is uncolored, as at the top of the screen.
    private func summary(_ day: Date, _ goals: DayGoals) -> some View {
        let t = goals.targets
        let isToday = day == today
        // A day with nothing logged isn't graded; it may be from before LiftLog.
        func near(_ value: Double, _ target: Int?) -> Goal? {
            guard goals.hasData, let target else { return nil }
            return isToday ? Goal.soFar(value, Double(target)) : Goal.near(value, Double(target))
        }
        func minimum(_ value: Double, _ goal: Double?) -> Goal? {
            guard let goal else { return nil }
            return isToday ? Goal.reaching(value, goal) : DayGoals.grade(value, goal)
        }
        func grams(_ value: Double) -> String { "\(Int(value.rounded()).formatted()) g" }
        var stats = [
            Stat(value: Int(goals.kcal.rounded()).formatted(), label: "kcal", state: near(goals.kcal, t?.kcal), target: t?.kcal.formatted()),
            Stat(value: grams(goals.protein), label: "protein", state: goals.hasData ? minimum(goals.protein, t.map { Double($0.protein) }) : nil,
                 target: t.map { grams(Double($0.protein)) }),
            Stat(value: grams(goals.carbs), label: "carbs", state: near(goals.carbs, t?.carbs), target: t.map { grams(Double($0.carbs)) }),
            Stat(value: grams(goals.fat), label: "fat", state: near(goals.fat, t?.fat), target: t.map { grams(Double($0.fat)) }),
            Stat(value: "\(Format.number(goals.water)) \(waterUnit.rawValue)", label: "water",
                 state: goals.hasData ? minimum(goals.water, goals.waterGoal) : nil,
                 target: goals.waterGoal.map { "\(Format.number($0)) \(waterUnit.rawValue)" }),
        ]
        if let count = steps[day] {
            let goal = Steps.goal(steps, on: day)
            stats.append(Stat(value: Int(count.rounded()).formatted(), label: "steps", state: minimum(count, Double(goal)), target: goal.formatted()))
        }
        return VStack(spacing: 8) {
            HStack {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday().month().day())).font(.footnote.weight(.semibold))
                Spacer()
                legend
            }
            HStack(alignment: .top, spacing: 2) {
                ForEach(stats) { stat in
                    VStack(spacing: 1) {
                        Text(stat.value)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(stat.state?.color ?? .primary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(stat.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stat.label) \(stat.value)\(stat.target.map { " of \($0)" } ?? "")\(stat.state.map { ", \(label($0))" } ?? "")")
                }
            }
        }
    }

    /// What the day colors mean: protein and water at their goals and calories within 10% of the day's target is green;
    /// within 15%, 20% for calories, is orange.
    private var legend: some View {
        HStack(spacing: 8) {
            ForEach([Goal.hit, .close, .missed], id: \.self) { goal in
                HStack(spacing: 3) {
                    Circle().fill(goal.color).frame(width: 7, height: 7)
                    Text(goal == .hit ? "Hit" : goal == .close ? "Close" : "Missed")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Green: protein and water goals hit and calories within 10%. Orange: close. Red: missed.")
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
