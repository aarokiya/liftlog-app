import Foundation

public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg

    public static let kilogramsPerPound = 0.45359237

    public func convert(_ value: Double, to target: WeightUnit) -> Double {
        switch (self, target) {
        case (.lb, .kg): return value * Self.kilogramsPerPound
        case (.kg, .lb): return value / Self.kilogramsPerPound
        default: return value
        }
    }
}

public enum SetType: String, Codable, CaseIterable, Sendable {
    case warmup
    case working
    case drop
    case failure

    public var countsTowardStats: Bool { self != .warmup }
}

/// A logged set reduced to what the stats engine needs. Weight is stored as entered, with its unit.
public struct LiftSet: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var sessionId: String
    public var weight: Double
    public var unit: WeightUnit
    public var reps: Int
    public var type: SetType

    public init(exerciseId: String, sessionId: String, weight: Double, unit: WeightUnit, reps: Int, type: SetType = .working) {
        self.exerciseId = exerciseId
        self.sessionId = sessionId
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.type = type
    }

    public func weight(in target: WeightUnit) -> Double {
        unit.convert(weight, to: target)
    }
}
