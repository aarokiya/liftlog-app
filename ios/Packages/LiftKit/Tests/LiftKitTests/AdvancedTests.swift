import Foundation
import XCTest
@testable import LiftKit

/// Same cases as web/src/lib/stats/advanced.test.ts.
final class AdvancedTests: XCTestCase {
    struct Fixtures: Decodable {
        struct Score: Decodable { let totalKg, bodyKg, wilks, dots: Double }
        struct BalanceCase: Decodable {
            struct Expected: Decodable { let pushPull, quadHam: Double? }
            let muscleSets: [String: Double]
            let expected: Expected
        }
        struct Load: Decodable { let day: Int; let load: Double }
        struct AcwrCase: Decodable { let loads: [Load]; let today: Int; let expected: Double? }
        struct Point: Decodable { let day, value: Double }
        struct PlateauCase: Decodable {
            struct Expected: Decodable { let weeklyChange: Double; let plateaued: Bool }
            let points: [Point]
            let expected: Expected
        }
        struct GrowthCase: Decodable {
            struct Expected: Decodable {
                let start, recent, best, change: Double
                let changePct, weeklyRate: Double?
                let prs: Int
                let lastPrDay: Double
                let sessions: Int
                let spanDays: Double
            }
            let points: [Point]
            let expected: Expected
        }
        let growth: [GrowthCase]
        let scores: [Score]
        let balance: [BalanceCase]
        let acwr: [AcwrCase]
        let plateau: [PlateauCase]
    }

    func testSharedFixtures() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        let fx = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url.appendingPathComponent("shared/fixtures/advanced-cases.json")))
        for c in fx.scores {
            XCTAssertEqual(Advanced.wilks(totalKg: c.totalKg, bodyKg: c.bodyKg), c.wilks)
            XCTAssertEqual(Advanced.dots(totalKg: c.totalKg, bodyKg: c.bodyKg), c.dots)
        }
        for c in fx.balance {
            XCTAssertEqual(Advanced.balance(c.muscleSets), .init(pushPull: c.expected.pushPull, quadHam: c.expected.quadHam))
        }
        for c in fx.acwr {
            XCTAssertEqual(Advanced.acwr(c.loads.map { (day: $0.day, load: $0.load) }, today: c.today), c.expected)
        }
        for c in fx.plateau {
            XCTAssertEqual(Advanced.plateau(c.points.map { (day: $0.day, value: $0.value) }),
                           .init(weeklyChange: c.expected.weeklyChange, plateaued: c.expected.plateaued))
        }
        for c in fx.growth {
            let e = c.expected
            XCTAssertEqual(Advanced.growth(c.points.map { (day: $0.day, value: $0.value) }),
                           .init(start: e.start, recent: e.recent, best: e.best, change: e.change, changePct: e.changePct,
                                 weeklyRate: e.weeklyRate, prs: e.prs, lastPrDay: e.lastPrDay, sessions: e.sessions, spanDays: e.spanDays))
        }
        XCTAssertNil(Advanced.growth([]))
        XCTAssertEqual(Advanced.muscleRecency(["chest": 10], today: 12), ["chest": 2])
        XCTAssertEqual(Advanced.density(volume: 5800, minutes: 58), 100)
        XCTAssertNil(Advanced.density(volume: 1, minutes: 0))
    }
}
