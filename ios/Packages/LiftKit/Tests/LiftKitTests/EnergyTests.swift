import Foundation
import XCTest
@testable import LiftKit

/// Runs shared/fixtures/energy-cases.json, the same cases as the web energy tests (web/src/lib/aesthetics).
final class EnergyTests: XCTestCase {
    struct TargetsJSON: Decodable {
        let kcal, protein, carbs, fat: Int
        var targets: Energy.Targets { Energy.Targets(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
    }

    struct BaseJSON: Decodable {
        let targets: TargetsJSON
        let kcalFloor: Int
        let fatFloor: Int
        var base: Energy.Base { Energy.Base(targets: targets.targets, kcalFloor: kcalFloor, fatFloor: fatFloor) }
    }

    struct MaintenanceCase: Decodable {
        let name: String
        let leanMassKg: Double
        let bmr: Double
        let formula: Int
    }

    struct LearnedCase: Decodable {
        let name: String
        let formula: Int
        let today: Int
        let intake: [String: Double]
        /// [day, kg] pairs.
        let weights: [[Double]]
        let expected: Int
    }

    struct BaseCase: Decodable {
        struct Plan: Decodable {
            let phase: String
            let leanMass, weeklyLow, weeklyHigh: Double
            let proteinG: Int
        }
        let name: String
        let plan: Plan
        let bodyWeight: Double
        let unit: String
        let maintenance: Int
        let sex: String
        let expected: BaseJSON
    }

    struct DailyCase: Decodable {
        struct IntakeJSON: Decodable { let kcal, fat: Double }
        let name: String
        let base: BaseJSON
        let from: Int
        let through: Int
        let intake: [String: IntakeJSON]
        let expected: [String: TargetsJSON]
    }

    struct Fixtures: Decodable {
        let maintenance: [MaintenanceCase]
        let learned: [LearnedCase]
        let base: [BaseCase]
        let daily: [DailyCase]
    }

    func testSharedFixtures() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/energy-cases.json")
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))

        XCTAssertFalse(fixtures.maintenance.isEmpty)
        for c in fixtures.maintenance {
            XCTAssertEqual(Energy.bmr(leanMassKg: c.leanMassKg), c.bmr, accuracy: 1e-6, c.name)
            XCTAssertEqual(Energy.formulaMaintenance(leanMassKg: c.leanMassKg), c.formula, c.name)
        }

        XCTAssertFalse(fixtures.learned.isEmpty)
        for c in fixtures.learned {
            var intake: [Int: Double] = [:]
            for (day, kcal) in c.intake { intake[Int(day)!] = kcal }
            let weights = c.weights.map { (day: Int($0[0]), kg: $0[1]) }
            XCTAssertEqual(Energy.learnedMaintenance(formula: c.formula, intake: intake, weightsKg: weights, today: c.today), c.expected, c.name)
        }

        XCTAssertFalse(fixtures.base.isEmpty)
        for c in fixtures.base {
            // Fixture plans carry only what Energy reads; the rest are placeholders.
            let plan = Aesthetics.BodyPlan(
                phase: Aesthetics.Phase(rawValue: c.plan.phase)!, leanMass: c.plan.leanMass, goalWeight: 0, checkpoint: 0, toLose: 0,
                weeklyLow: c.plan.weeklyLow, weeklyHigh: c.plan.weeklyHigh, weeks: nil, proteinG: c.plan.proteinG
            )
            let base = Energy.base(plan: plan, bodyWeight: c.bodyWeight, unit: WeightUnit(rawValue: c.unit)!, maintenance: c.maintenance,
                                   sex: c.sex == "female" ? .female : .male)
            XCTAssertEqual(base, c.expected.base, c.name)
        }

        XCTAssertFalse(fixtures.daily.isEmpty)
        for c in fixtures.daily {
            var intake: [Int: Energy.Intake] = [:]
            for (day, i) in c.intake { intake[Int(day)!] = Energy.Intake(kcal: i.kcal, fat: i.fat) }
            var expected: [Int: Energy.Targets] = [:]
            for (day, t) in c.expected { expected[Int(day)!] = t.targets }
            XCTAssertEqual(Energy.daily(base: c.base.base, intake: intake, from: c.from, through: c.through), expected, c.name)
        }
    }
}
