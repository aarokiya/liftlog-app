import Foundation

/// Always encodes its key, writing `null` when empty, so clearing a field on the phone clears it on the server.
struct Nullable<T: Codable & Sendable>: Codable, Sendable {
    var value: T?

    init(_ value: T?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = container.decodeNil() ? nil : try container.decode(T.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }
}

/// Mirrors a Supabase table row. `updated_at` is set by the server and omitted on push.
protocol RemoteRow: Codable, Sendable {
    var id: UUID { get }
    var updated_at: Date? { get }
}

struct ProfileRow: Codable, Sendable {
    var id: UUID
    var display_name: Nullable<String>
    var default_unit: String
    var e1rm_formula: String
    var weekly_workout_target: Int
    var bar_weight: Double
    var height_cm: Nullable<Double>
    var active_program: Nullable<String>
    var campus: Nullable<String>
    var sex: Nullable<String>
}

struct ExerciseRow: RemoteRow {
    var id: UUID
    var user_id: UUID?
    var name: String
    var kind: String
    var equipment: Nullable<String>
    var primary_muscle: String
    var secondary_muscles: [String]
    var default_rest_seconds: Int
    var sticky_note: Nullable<String>
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct RoutineRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var name: String
    var notes: Nullable<String>
    var position: Int
    var program: Nullable<String>
    var program_day: Nullable<Int>
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct RoutineExerciseRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var routine_id: UUID
    var exercise_id: UUID
    var position: Int
    var superset_group: Nullable<Int>
    var target_sets: Int
    var rep_min: Nullable<Int>
    var rep_max: Nullable<Int>
    var rest_seconds: Nullable<Int>
    var notes: Nullable<String>
    var attachment: Nullable<String>
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct WorkoutRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var routine_id: Nullable<UUID>
    var name: String
    var notes: Nullable<String>
    var started_at: Date
    var ended_at: Nullable<Date>
    var timezone: String
    var source: String
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct WorkoutExerciseRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var workout_id: UUID
    var exercise_id: UUID
    var position: Int
    var superset_group: Nullable<Int>
    var notes: Nullable<String>
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct SetRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var workout_exercise_id: UUID
    var position: Int
    var set_type: String
    var weight: Nullable<Double>
    var weight_unit: String
    var reps: Nullable<Int>
    var duration_seconds: Nullable<Int>
    var rpe: Nullable<Double>
    var notes: Nullable<String>
    var completed_at: Nullable<Date>
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct BodyMetricRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var measured_at: Date
    var body_weight: Nullable<Double>
    var unit: String
    var body_fat_pct: Nullable<Double>
    var waist_cm: Nullable<Double>
    var neck_cm: Nullable<Double>
    var hips_cm: Nullable<Double>
    var source: String
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct FoodLogRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var eaten_at: Date
    var meal: String
    var source: String
    var place: Nullable<String>
    var name: String
    var serving: Nullable<String>
    var servings: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}

struct WaterLogRow: RemoteRow {
    var id: UUID
    var user_id: UUID
    var drank_at: Date
    var amount: Double
    var unit: String
    var deleted_at: Nullable<Date>
    var updated_at: Date?
}
