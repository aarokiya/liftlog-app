import Foundation

/// Mirrors web/src/lib/stats/advanced.ts; both are checked against shared/fixtures/advanced-cases.json.
public enum Advanced {
    public enum Sex: Sendable { case male, female }

    private static func poly(_ x: Double, _ coeffs: [Double]) -> Double {
        coeffs.enumerated().reduce(0) { $0 + $1.element * pow(x, Double($1.offset)) }
    }

    private static func round(_ v: Double, _ places: Double) -> Double {
        let f = pow(10, places)
        return (v * f).rounded() / f
    }

    private static let wilksCoeffs: [Sex: [Double]] = [
        .male: [-216.0475144, 16.2606339, -0.002388645, -0.00113732, 7.01863e-6, -1.291e-8],
        .female: [594.31747775582, -27.23842536447, 0.82112226871, -0.00930733913, 4.731582e-5, -9.054e-8],
    ]
    private static let dotsCoeffs: [Sex: [Double]] = [
        .male: [-307.75076, 24.0900756, -0.1918759221, 0.0007391293, -0.000001093],
        .female: [-57.96288, 13.6175032, -0.1126655495, 0.0005158568, -0.0000010706],
    ]

    public static func wilks(totalKg: Double, bodyKg: Double, sex: Sex = .male) -> Double? {
        guard totalKg > 0, bodyKg > 0 else { return nil }
        return round(totalKg * 500 / poly(bodyKg, wilksCoeffs[sex]!), 2)
    }

    public static func dots(totalKg: Double, bodyKg: Double, sex: Sex = .male) -> Double? {
        guard totalKg > 0, bodyKg > 0 else { return nil }
        return round(totalKg * 500 / poly(bodyKg, dotsCoeffs[sex]!), 2)
    }

    public struct Plateau: Equatable, Sendable {
        public let weeklyChange: Double
        public let plateaued: Bool
    }

    /// Under 0.5%/week e1RM change across at least `minSessions` sessions counts as a plateau.
    public static func plateau(_ points: [(day: Double, value: Double)], minSessions: Int = 4) -> Plateau? {
        guard points.count >= minSessions,
              let line = Trend.linearRegression(points.map { (x: $0.day, y: $0.value) }) else { return nil }
        let mean = points.reduce(0) { $0 + $1.value } / Double(points.count)
        guard mean > 0 else { return nil }
        let weekly = round(line.slope * 7 / mean, 4)
        return Plateau(weeklyChange: weekly, plateaued: weekly < 0.005)
    }

    public struct Balance: Equatable, Sendable {
        public let pushPull: Double?
        public let quadHam: Double?
    }

    public static func balance(_ muscleSets: [String: Double]) -> Balance {
        func sum(_ keys: [String]) -> Double { keys.reduce(0) { $0 + (muscleSets[$1] ?? 0) } }
        func ratio(_ a: Double, _ b: Double) -> Double? { b > 0 ? round(a / b, 2) : nil }
        return Balance(
            pushPull: ratio(sum(["chest", "front_delts", "triceps"]), sum(["back", "rear_delts", "biceps"])),
            quadHam: ratio(sum(["quads"]), sum(["hamstrings"]))
        )
    }

    /// Acute:chronic workload ratio: last 7 days' load vs. the weekly average of the last 28.
    /// Needs four weeks of history (the earliest load at least 27 days back); before that both windows hold the same
    /// sessions and the ratio means nothing.
    public static func acwr(_ loads: [(day: Int, load: Double)], today: Int) -> Double? {
        guard let first = loads.map(\.day).min(), today - first >= 27 else { return nil }
        func within(_ days: Int) -> Double {
            loads.filter { $0.day > today - days && $0.day <= today }.reduce(0) { $0 + $1.load }
        }
        let chronic = within(28) / 4
        return chronic > 0 ? round(within(7) / chronic, 2) : nil
    }

    public static func muscleRecency(_ lastDay: [String: Int], today: Int) -> [String: Int] {
        lastDay.mapValues { today - $0 }
    }

    public static func density(volume: Double, minutes: Double) -> Double? {
        minutes > 0 ? round(volume / minutes, 1) : nil
    }

    public struct Growth: Equatable, Sendable {
        public let start: Double
        public let recent: Double
        public let best: Double
        public let change: Double
        public let changePct: Double?
        public let weeklyRate: Double?
        public let prs: Int
        public let lastPrDay: Double
        public let sessions: Int
        public let spanDays: Double
    }

    /// First session vs. the best of the last 3, weekly regression slope, and sessions that set a new best.
    public static func growth(_ points: [(day: Double, value: Double)]) -> Growth? {
        guard !points.isEmpty else { return nil }
        let sorted = points.sorted { $0.day < $1.day }
        let start = sorted[0].value
        let recent = sorted.suffix(3).map(\.value).max()!
        var best = start
        var prs = 0
        var lastPrDay = sorted[0].day
        for p in sorted.dropFirst() where p.value > best {
            best = p.value
            prs += 1
            lastPrDay = p.day
        }
        let line = Trend.linearRegression(sorted.map { (x: $0.day, y: $0.value) })
        return Growth(
            start: start,
            recent: recent,
            best: best,
            change: round(recent - start, 1),
            changePct: start > 0 ? round((recent - start) / start * 100, 1) : nil,
            weeklyRate: line.map { round($0.slope * 7, 1) },
            prs: prs,
            lastPrDay: lastPrDay,
            sessions: sorted.count,
            spanDays: sorted.last!.day - sorted[0].day
        )
    }
}
