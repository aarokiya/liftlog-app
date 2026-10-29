import Foundation

/// A calendar date without time or timezone, so weekly stats don't shift when travelling.
public struct LocalDate: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`.
    public init?(_ iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Monday-based week index. 1970-01-01 was a Thursday.
    public var weekNumber: Int {
        let shifted = dayNumber + 3
        return shifted >= 0 ? shifted / 7 : (shifted - 6) / 7
    }

    public static func < (a: LocalDate, b: LocalDate) -> Bool { a.dayNumber < b.dayNumber }
}

public enum Streaks {
    public struct Result: Equatable, Sendable {
        public let current: Int
        public let longest: Int
    }

    /// Counts consecutive Monday-based weeks with at least `target` workouts.
    /// The in-progress week never breaks the current streak.
    public static func weekly(workoutDates: [LocalDate], target: Int, asOf: LocalDate) -> Result {
        var perWeek: [Int: Int] = [:]
        for d in workoutDates { perWeek[d.weekNumber, default: 0] += 1 }
        let qualifying = Set(perWeek.filter { $0.value >= target }.keys)

        var longest = 0
        var run = 0
        var previous: Int?
        for w in qualifying.sorted() {
            run = (previous.map { w == $0 + 1 } ?? false) ? run + 1 : 1
            longest = max(longest, run)
            previous = w
        }

        var week = asOf.weekNumber
        if !qualifying.contains(week) { week -= 1 }
        var current = 0
        while qualifying.contains(week) {
            current += 1
            week -= 1
        }
        return Result(current: current, longest: longest)
    }
}
