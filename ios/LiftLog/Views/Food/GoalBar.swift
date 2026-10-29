import LiftKit
import SwiftUI

/// A MyFitnessPal-style progress row: the label and "eaten / target" over a bar, with what's left (or over) on the
/// right. The bar is green, orange or red by `state` and neutral while that's nil, e.g. today's calories while still
/// under. Without a target it's just the amount.
struct GoalBar: View {
    var label: String?
    let value: Double
    let target: Double?
    /// After the amounts, e.g. "g"; empty when the label already says it ("Calories", steps).
    var unit = ""
    let state: Goal?
    /// Whole numbers by default; water keeps a decimal.
    var format: (Double) -> String = { Int($0.rounded()).formatted() }

    private func withUnit(_ text: String) -> String { unit.isEmpty ? text : "\(text) \(unit)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let label { Text(label).font(.subheadline.weight(.medium)) }
                (Text(format(value)).fontWeight(.semibold) + Text(withUnit(target.map { " / \(format($0))" } ?? "")).foregroundStyle(.secondary))
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let target {
                    Text(value <= target ? "\(withUnit(format(target - value))) left" : "\(withUnit(format(value - target))) over")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(state == .missed ? Goal.missed.color : .secondary)
                        .lineLimit(1)
                }
            }
            if let target {
                bar(target > 0 ? min(max(value / target, 0), 1) : 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            Capsule().fill(Color(.tertiarySystemFill))
                .overlay(alignment: .leading) {
                    Capsule().fill(state?.color ?? .accentColor)
                        // Anything logged shows at least a dot.
                        .frame(width: value > 0 ? max(geo.size.height, geo.size.width * fraction) : 0)
                }
        }
        .frame(height: 6)
        .animation(.easeOut, value: fraction)
    }
}

extension Goal {
    /// A daily minimum (protein, water, steps) while the day is still going: hit at the goal, close from 85% of it, and
    /// nil below that rather than missed.
    static func reaching(_ value: Double, _ goal: Double) -> Goal? {
        let state = DayGoals.grade(value, goal)
        return state == .missed ? nil : state
    }
}

extension Steps {
    /// Health's daily counts (keyed by start of day) by day number.
    private static func byDay(_ steps: [Date: Double]) -> [Int: Double] {
        Dictionary(steps.map { (LocalDate(date: $0.key).dayNumber, $0.value) }, uniquingKeysWith: +)
    }

    /// `goal(steps:today:)` for `day`, from Health's daily counts keyed by start of day.
    static func goal(_ steps: [Date: Double], on day: Date) -> Int {
        goal(steps: byDay(steps), today: LocalDate(date: day).dayNumber)
    }

    /// `baseline(steps:today:)` for `day`, from Health's daily counts keyed by start of day.
    static func baseline(_ steps: [Date: Double], on day: Date) -> Double? {
        baseline(steps: byDay(steps), today: LocalDate(date: day).dayNumber)
    }
}
