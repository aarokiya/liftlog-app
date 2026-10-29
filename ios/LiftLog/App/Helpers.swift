import LiftKit
import SwiftUI

extension Binding {
    /// Runs `action` after every write, e.g. to mark a model dirty for sync.
    func onSet(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; action() })
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension Advanced.Sex {
    /// The `Prefs.sex` setting; nil when it isn't set.
    init?(pref: String) {
        switch pref {
        case "male": self = .male
        case "female": self = .female
        default: return nil
        }
    }
}

/// Goal states shown in green, orange and red across the app.
enum Goal {
    case hit, close, missed

    var color: Color {
        switch self {
        case .hit: .green
        case .close: .orange
        case .missed: .red
        }
    }

    /// Hit inside `range`, close within `slack` of it, otherwise missed.
    static func band(_ value: Double, _ range: ClosedRange<Double>, slack: Double) -> Goal {
        range.contains(value) ? .hit : (range.lowerBound - slack...range.upperBound + slack).contains(value) ? .close : .missed
    }
}

enum Format {
    /// "ez_bar" -> "EZ bar", "plate_machine" -> "Plate machine".
    static func equipment(_ raw: String) -> String {
        let words = raw.split(separator: "_").map { $0 == "ez" ? "EZ" : String($0) }
        let text = words.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func weight(_ value: Double, _ unit: WeightUnit) -> String {
        "\(number(value)) \(unit.rawValue)"
    }

    static func volume(_ value: Double, _ unit: WeightUnit) -> String {
        "\(Int(value.rounded()).formatted()) \(unit.rawValue)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .hourMinute))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}
