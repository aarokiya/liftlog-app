import XCTest
@testable import LiftKit

/// Steps are phone-only (Apple Health), so these cases aren't shared with the web.
final class StepsTests: XCTestCase {
    private let today = 20000

    /// `values[0]` is yesterday, `values[1]` the day before, and so on.
    private func days(_ values: [Double]) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: values.enumerated().map { (today - 1 - $0.offset, $0.element) })
    }

    func testDefaultUntilAWeekOfHistory() {
        XCTAssertNil(Steps.baseline(steps: days(Array(repeating: 9000, count: 6)), today: today))
        XCTAssertEqual(Steps.goal(steps: [:], today: today), Steps.defaultGoal)
        XCTAssertEqual(Steps.goal(steps: days(Array(repeating: 9000, count: 6)), today: today), 8000)
        XCTAssertEqual(Steps.goal(steps: days(Array(repeating: 9000, count: 7)), today: today), 10000)
    }

    func testMedianPlusTenPercentRoundedUp() {
        // Median 7,000 → 7,700 → 8,000.
        XCTAssertEqual(Steps.goal(steps: days([4000, 7000, 12000, 6500, 7000, 9000, 7500]), today: today), 8000)
        // Even count: median of 6,000 and 8,000 is 7,000.
        XCTAssertEqual(Steps.baseline(steps: days([5000, 6000, 8000, 9000, 6000, 8000, 5000, 9000]), today: today), 7000)
        // Exactly on a step of 500 stays there.
        XCTAssertEqual(Steps.goal(steps: days(Array(repeating: 10000, count: 10)), today: today), 11000)
    }

    func testSkipsPhoneLeftBehindTodayAndOldDays() {
        var steps = days([8000, 800, 8000, 8000, 8000, 950, 8000, 8000])
        steps[today] = 30000
        steps[today - 29] = 30000
        // Six valid days: the two under 1,000, today and day 29 don't count.
        XCTAssertNil(Steps.baseline(steps: steps, today: today))
        steps[today - 28] = 8000
        XCTAssertEqual(Steps.baseline(steps: steps, today: today), 8000)
    }

    func testOnlyTheLast14ValidDays() {
        let recent = Array(repeating: 6000.0, count: 14)
        let older = Array(repeating: 15000.0, count: 14)
        XCTAssertEqual(Steps.baseline(steps: days(recent + older), today: today), 6000)
    }

    func testClamped() {
        XCTAssertEqual(Steps.goal(steps: days(Array(repeating: 2000, count: 14)), today: today), 5000)
        XCTAssertEqual(Steps.goal(steps: days(Array(repeating: 18000, count: 14)), today: today), 12000)
    }
}
