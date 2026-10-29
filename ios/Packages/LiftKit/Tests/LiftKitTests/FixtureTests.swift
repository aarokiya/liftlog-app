import Foundation
import XCTest
@testable import LiftKit

/// Runs the shared golden cases in `shared/fixtures/stats-cases.json`; the web test suite runs the same file.
final class FixtureTests: XCTestCase {
    struct Fixtures: Decodable {
        struct Conversion: Decodable { let value: Double; let from: WeightUnit; let to: WeightUnit; let expected: Double }
        struct E1RM: Decodable { let weight: Double; let reps: Int; let formula: OneRepMaxFormula; let expected: Double? }
        struct VolumeCase: Decodable { let sets: [LiftSet]; let unit: WeightUnit; let expected: Double }
        struct RepMaxCase: Decodable { let sets: [LiftSet]; let unit: WeightUnit; let expected: [String: Double] }
        struct SessionBest: Decodable { let sessionId: String; let value: Double }
        struct BestPerSession: Decodable { let sets: [LiftSet]; let unit: WeightUnit; let formula: OneRepMaxFormula; let expected: [SessionBest] }
        struct MuscleCase: Decodable { let exercises: [String: ExerciseMuscles]; let sets: [LiftSet]; let expected: [String: Double] }
        struct PlateExpected: Decodable { let perSide: [Double]; let remainder: Double }
        struct PlateCase: Decodable { let target: Double; let bar: Double; let available: [Double]; let expected: PlateExpected }
        struct StreakExpected: Decodable { let current: Int; let longest: Int }
        struct StreakCase: Decodable { let dates: [String]; let target: Int; let asOf: String; let expected: StreakExpected }
        struct Line: Decodable { let slope: Double; let intercept: Double }
        struct RegressionCase: Decodable { let points: [[Double]]; let expected: Line? }

        let conversion: [Conversion]
        let e1rm: [E1RM]
        let volume: [VolumeCase]
        let repMaxes: [RepMaxCase]
        let bestE1RMPerSession: [BestPerSession]
        let muscleSets: [MuscleCase]
        let plates: [PlateCase]
        let streaks: [StreakCase]
        let regression: [RegressionCase]
    }

    static let fixtures: Fixtures = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LiftKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // LiftKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("shared/fixtures/stats-cases.json")
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(Fixtures.self, from: data)
    }()

    let accuracy = 1e-6

    func testConversion() {
        for c in Self.fixtures.conversion {
            XCTAssertEqual(c.from.convert(c.value, to: c.to), c.expected, accuracy: accuracy)
        }
    }

    func testE1RM() {
        for c in Self.fixtures.e1rm {
            let got = OneRepMax.estimate(weight: c.weight, reps: c.reps, formula: c.formula)
            if let expected = c.expected {
                XCTAssertEqual(got ?? .nan, expected, accuracy: accuracy, "\(c)")
            } else {
                XCTAssertNil(got, "\(c)")
            }
        }
    }

    func testVolume() {
        for c in Self.fixtures.volume {
            XCTAssertEqual(Volume.load(c.sets, unit: c.unit), c.expected, accuracy: accuracy)
        }
    }

    func testRepMaxes() {
        for c in Self.fixtures.repMaxes {
            let got = PersonalRecords.repMaxes(c.sets, unit: c.unit)
            XCTAssertEqual(Set(got.keys.map(String.init)), Set(c.expected.keys))
            for (k, v) in c.expected {
                XCTAssertEqual(got[Int(k)!] ?? .nan, v, accuracy: accuracy)
            }
        }
    }

    func testBestE1RMPerSession() {
        for c in Self.fixtures.bestE1RMPerSession {
            let got = OneRepMax.bestPerSession(c.sets, unit: c.unit, formula: c.formula)
            XCTAssertEqual(got.map(\.sessionId), c.expected.map(\.sessionId))
            for (g, e) in zip(got, c.expected) { XCTAssertEqual(g.value, e.value, accuracy: accuracy) }
        }
    }

    func testMuscleSets() {
        for c in Self.fixtures.muscleSets {
            XCTAssertEqual(MuscleSets.count(c.sets, exercises: c.exercises), c.expected)
        }
    }

    func testPlates() {
        for c in Self.fixtures.plates {
            let got = PlateCalculator.plates(target: c.target, bar: c.bar, available: c.available)
            XCTAssertEqual(got.perSide, c.expected.perSide, "\(c.target)")
            XCTAssertEqual(got.remainder, c.expected.remainder, accuracy: accuracy)
        }
    }

    func testStreaks() {
        for c in Self.fixtures.streaks {
            let got = Streaks.weekly(workoutDates: c.dates.compactMap(LocalDate.init), target: c.target, asOf: LocalDate(c.asOf)!)
            XCTAssertEqual(got.current, c.expected.current, c.asOf)
            XCTAssertEqual(got.longest, c.expected.longest, c.asOf)
        }
    }

    func testRegression() {
        for c in Self.fixtures.regression {
            let got = Trend.linearRegression(c.points.map { (x: $0[0], y: $0[1]) })
            if let e = c.expected {
                XCTAssertEqual(got?.slope ?? .nan, e.slope, accuracy: accuracy)
                XCTAssertEqual(got?.intercept ?? .nan, e.intercept, accuracy: accuracy)
            } else {
                XCTAssertNil(got)
            }
        }
    }

    func testLocalDateDayNumber() {
        XCTAssertEqual(LocalDate("1970-01-01")!.dayNumber, 0)
        XCTAssertEqual(LocalDate("2000-03-01")!.dayNumber, 11_017)
        XCTAssertEqual(LocalDate("1970-01-05")!.weekNumber, 1)
        XCTAssertEqual(LocalDate("1970-01-04")!.weekNumber, 0)
    }
}
