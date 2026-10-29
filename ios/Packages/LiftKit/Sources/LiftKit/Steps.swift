import Foundation

/// A daily step goal from the user's own recent days in Apple Health. Steps never leave the phone, so unlike the rest
/// of LiftKit this has no TypeScript twin or shared fixture.
public enum Steps {
    /// The goal until there's a week of history: the low end of where the benefit of more steps levels off for adults
    /// under 60 (8,000–10,000 a day; Paluch et al., Lancet Public Health 2022).
    public static let defaultGoal = 8000
    public static let goalRange = 5000...12000

    /// The typical day lately: the median of the last 14 valid days among the 28 before `today` (today is still going).
    /// A day under 1,000 steps means the phone stayed behind, so it's skipped; the median shrugs off the odd hike or sick
    /// day. nil with fewer than 7 valid days. steps: total per day number (LocalDate.dayNumber).
    public static func baseline(steps: [Int: Double], today: Int) -> Double? {
        let recent = steps.filter { today - 28 <= $0.key && $0.key <= today - 1 && $0.value >= 1000 }
            .sorted { $0.key > $1.key }.prefix(14).map(\.value).sorted()
        guard recent.count >= 7 else { return nil }
        let mid = recent.count / 2
        return recent.count % 2 == 0 ? (recent[mid - 1] + recent[mid]) / 2 : recent[mid]
    }

    /// Today's goal: `baseline` plus 10%, rounded up to the next 500 and kept within 5,000–12,000; `defaultGoal` without
    /// a baseline. A goal a little above your own recent days stays within reach and rises as you walk more, which
    /// raises step counts more than a fixed 10,000 (adaptive goals, Adams et al. 2013 and 2017).
    public static func goal(steps: [Int: Double], today: Int) -> Int {
        guard let baseline = baseline(steps: steps, today: today) else { return defaultGoal }
        // Rounded before dividing, so 10,000 × 1.1 lands on 11,000 rather than a hair over it.
        let goal = Int(((baseline * 1.1).rounded() / 500).rounded(.up)) * 500
        return min(max(goal, goalRange.lowerBound), goalRange.upperBound)
    }
}
