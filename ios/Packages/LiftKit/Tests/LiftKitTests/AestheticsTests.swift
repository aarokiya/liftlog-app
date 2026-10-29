import Foundation
import XCTest
@testable import LiftKit

/// Same cases as web/src/lib/aesthetics/aesthetics.test.ts.
final class AestheticsTests: XCTestCase {
    struct Case: Decodable {
        let name: String
        let heightCm: Double
        let waistCm: Double
        let neckCm: Double
        let bodyFatPct: Double
        let waistToHeight: Double
    }

    struct RFMCase: Decodable {
        let name: String
        let heightCm: Double
        let waistCm: Double
        let hipsCm: Double
        let bodyFatPct: Double
        let waistToHip: Double
        let shoulderTarget: Double
    }

    struct PlanCase: Decodable {
        struct Expected: Decodable {
            let phase: String
            let leanMass, goalWeight, checkpoint, toLose, weeklyLow, weeklyHigh: Double
            let weeks: Int?
            let proteinG: Int
        }
        let name: String
        let bodyWeight: Double
        let unit: String
        let bodyFatPct: Double
        let goalPct: Double?
        let startWeight: Double?
        let sex: String?
        let expected: Expected
    }

    struct FemaleNavyCase: Decodable {
        let name: String
        let heightCm, waistCm, hipsCm, neckCm, bodyFatPct: Double
    }

    struct FemaleRFMCase: Decodable {
        let name: String
        let heightCm, waistCm, bodyFatPct: Double
    }

    struct Fixtures: Decodable {
        let navy_male: [Case]
        let rfm_male: [RFMCase]
        let navy_female: [FemaleNavyCase]
        let rfm_female: [FemaleRFMCase]
        let body_plan: [PlanCase]
    }

    func testSharedFixtures() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/aesthetics-cases.json")
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        XCTAssertFalse(fixtures.navy_male.isEmpty)
        XCTAssertFalse(fixtures.rfm_male.isEmpty)
        for c in fixtures.rfm_male {
            XCTAssertEqual(Aesthetics.rfmMale(heightCm: c.heightCm, waistCm: c.waistCm), c.bodyFatPct, c.name)
            XCTAssertEqual(Aesthetics.waistToHip(waistCm: c.waistCm, hipsCm: c.hipsCm), c.waistToHip, c.name)
            XCTAssertEqual(Aesthetics.shoulderTarget(waistCm: c.waistCm), c.shoulderTarget, c.name)
        }
        XCTAssertNil(Aesthetics.rfmMale(heightCm: 180, waistCm: 0))
        XCTAssertFalse(fixtures.body_plan.isEmpty)
        for c in fixtures.body_plan {
            let plan = Aesthetics.bodyPlan(bodyWeight: c.bodyWeight, unit: WeightUnit(rawValue: c.unit)!, bodyFatPct: c.bodyFatPct, goalPct: c.goalPct, startWeight: c.startWeight,
                                           sex: c.sex == "female" ? .female : .male)
            let e = c.expected
            XCTAssertEqual(plan, Aesthetics.BodyPlan(
                phase: Aesthetics.Phase(rawValue: e.phase)!, leanMass: e.leanMass, goalWeight: e.goalWeight, checkpoint: e.checkpoint, toLose: e.toLose,
                weeklyLow: e.weeklyLow, weeklyHigh: e.weeklyHigh, weeks: e.weeks, proteinG: e.proteinG
            ), c.name)
        }
        for c in fixtures.navy_male {
            XCTAssertEqual(Aesthetics.navyBodyFatMale(heightCm: c.heightCm, waistCm: c.waistCm, neckCm: c.neckCm), c.bodyFatPct, c.name)
            XCTAssertEqual(Aesthetics.waistToHeight(waistCm: c.waistCm, heightCm: c.heightCm), c.waistToHeight, c.name)
        }
        XCTAssertNil(Aesthetics.navyBodyFatMale(heightCm: 180, waistCm: 40, neckCm: 40))
        XCTAssertFalse(fixtures.navy_female.isEmpty)
        for c in fixtures.navy_female {
            XCTAssertEqual(Aesthetics.navyBodyFatFemale(heightCm: c.heightCm, waistCm: c.waistCm, hipsCm: c.hipsCm, neckCm: c.neckCm), c.bodyFatPct, c.name)
            XCTAssertEqual(Aesthetics.bodyFatEstimate(sex: .female, heightCm: c.heightCm, waistCm: c.waistCm, neckCm: c.neckCm, hipsCm: c.hipsCm), c.bodyFatPct, c.name)
        }
        for c in fixtures.rfm_female {
            XCTAssertEqual(Aesthetics.rfmFemale(heightCm: c.heightCm, waistCm: c.waistCm), c.bodyFatPct, c.name)
            XCTAssertEqual(Aesthetics.bodyFatEstimate(sex: .female, heightCm: c.heightCm, waistCm: c.waistCm, neckCm: nil, hipsCm: nil), c.bodyFatPct, c.name)
        }
        XCTAssertEqual(Aesthetics.band(0.55), .elevated)
    }
}
