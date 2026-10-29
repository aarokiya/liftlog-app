import Foundation
import LiftKit
import SwiftData

/// Rows that sync with Supabase: client-generated ids, `updatedAt` for last-write-wins,
/// `deletedAt` tombstones, and `needsSync` for rows changed since the last push.
protocol SyncedModel: AnyObject {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var needsSync: Bool { get set }
}

extension SyncedModel {
    /// Marks the row changed and saves right away, so edits survive the app being killed.
    func touch() {
        updatedAt = .now
        needsSync = true
        try? (self as? any PersistentModel)?.modelContext?.save()
    }

    func softDelete() {
        deletedAt = .now
        touch()
    }

    var isLive: Bool { deletedAt == nil }
}

@Model
final class Exercise: SyncedModel {
    @Attribute(.unique) var id: UUID
    var isBuiltIn: Bool
    var name: String
    var kind: String
    var equipment: String?
    var primaryMuscle: String
    var secondaryMuscles: [String]
    var defaultRestSeconds: Int
    var stickyNote: String?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool
    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise) var workoutExercises: [WorkoutExercise] = []
    @Relationship(deleteRule: .nullify, inverse: \RoutineExercise.exercise) var routineExercises: [RoutineExercise] = []

    init(
        id: UUID = UUID(), isBuiltIn: Bool = false, name: String, kind: String = "weight_reps",
        equipment: String? = nil, primaryMuscle: String, secondaryMuscles: [String] = [], defaultRestSeconds: Int = 120
    ) {
        self.id = id
        self.isBuiltIn = isBuiltIn
        self.name = name
        self.kind = kind
        self.equipment = equipment
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.defaultRestSeconds = defaultRestSeconds
        self.updatedAt = .now
        self.needsSync = !isBuiltIn
    }

    var muscles: ExerciseMuscles { ExerciseMuscles(primary: primaryMuscle, secondary: secondaryMuscles) }

    /// Sets from the most recent finished workout before `date`, used to prefill weight and reps.
    func lastSets(before date: Date) -> [WorkoutSet] {
        workoutExercises
            .filter { we in
                guard we.isLive, let workout = we.workout, workout.isLive, !workout.isInProgress else { return false }
                return workout.startedAt < date
            }
            .max { ($0.workout?.startedAt ?? .distantPast) < ($1.workout?.startedAt ?? .distantPast) }?
            .liveSets ?? []
    }
}

@Model
final class Workout: SyncedModel {
    @Attribute(.unique) var id: UUID
    var routineId: UUID?
    var name: String
    var notes: String?
    var startedAt: Date
    var endedAt: Date?
    var timezone: String
    var source: String
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool
    /// Local only: when this workout was written to Apple Health.
    var healthExportedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout) var exercises: [WorkoutExercise] = []

    init(id: UUID = UUID(), name: String, routineId: UUID? = nil, startedAt: Date = .now) {
        self.id = id
        self.name = name
        self.routineId = routineId
        self.startedAt = startedAt
        self.timezone = TimeZone.current.identifier
        self.source = "app"
        self.updatedAt = .now
        self.needsSync = true
    }

    var liveExercises: [WorkoutExercise] {
        exercises.filter(\.isLive).sorted { $0.position < $1.position }
    }

    var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }

    /// Only workouts started in the app can be in progress. Web and imported workouts may have no end
    /// time (unknown duration) but are finished.
    var isInProgress: Bool { endedAt == nil && source == "app" }

    static var inProgress: Predicate<Workout> {
        #Predicate { $0.deletedAt == nil && $0.endedAt == nil && $0.source == "app" }
    }

    static var finished: Predicate<Workout> {
        #Predicate { $0.deletedAt == nil && ($0.endedAt != nil || $0.source != "app") }
    }

    /// Logged sets as stats input. Sets without a weight are skipped unless `includingBodyweight`, which keeps them
    /// (as 0) for counting sets per muscle; volume, e1RM and PRs always use weighted sets only.
    func liftSets(includingBodyweight: Bool = false) -> [LiftSet] {
        liveExercises.flatMap { we -> [LiftSet] in
            guard let exercise = we.exercise else { return [] }
            return we.liveSets.compactMap { set in
                guard let reps = set.reps, reps > 0, set.weight != nil || includingBodyweight else { return nil }
                return LiftSet(
                    exerciseId: exercise.id.uuidString, sessionId: id.uuidString,
                    weight: set.weight ?? 0, unit: set.unit, reps: reps, type: set.setType
                )
            }
        }
    }

    @discardableResult
    func add(_ exercise: Exercise, sets count: Int = 1, unit: WeightUnit, context: ModelContext) -> WorkoutExercise {
        let we = WorkoutExercise(position: (exercises.map(\.position).max() ?? -1) + 1)
        context.insert(we)
        we.workout = self
        we.exercise = exercise
        let previous = exercise.lastSets(before: startedAt)
        for index in 0..<max(1, count) {
            we.addSet(unit: unit, context: context, template: previous[safe: index])
        }
        touch()
        return we
    }

    /// Ends the workout. Unticked sets you typed into count as done, with blanks filled from their placeholders;
    /// untouched sets and sets without reps are dropped, and a workout left with nothing is discarded.
    func finish() {
        let now = Date.now
        for we in liveExercises {
            let sets = we.liveSets
            let previous = we.previousSets
            for (index, set) in sets.enumerated() {
                if set.completedAt == nil {
                    guard set.weight != nil || set.reps != nil else {
                        set.softDelete()
                        continue
                    }
                    let hint = we.placeholder(at: index, in: sets, previous: previous)
                    if set.weight == nil { set.weight = hint.weight }
                    if set.reps == nil { set.reps = hint.reps }
                    if (set.reps ?? 0) > 0 { set.completedAt = now }
                }
                if (set.reps ?? 0) > 0 { set.touch() } else { set.softDelete() }
            }
            if we.liveSets.isEmpty { we.softDelete() }
        }
        endedAt = .now
        if liveExercises.isEmpty { deletedAt = now }
        touch()
    }

    static func start(routine: Routine?, unit: WeightUnit, context: ModelContext) -> Workout {
        let workout = Workout(name: routine?.name ?? defaultName(), routineId: routine?.id)
        context.insert(workout)
        for item in routine?.liveItems ?? [] {
            if let exercise = item.exercise {
                workout.add(exercise, sets: item.targetSets, unit: unit, context: context)
            }
        }
        return workout
    }

    static func defaultName(for date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case ..<12: "Morning Workout"
        case ..<17: "Afternoon Workout"
        default: "Evening Workout"
        }
    }
}

@Model
final class WorkoutExercise: SyncedModel {
    @Attribute(.unique) var id: UUID
    var workout: Workout?
    var exercise: Exercise?
    var position: Int
    var supersetGroup: Int?
    var notes: String?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise) var sets: [WorkoutSet] = []

    init(id: UUID = UUID(), position: Int) {
        self.id = id
        self.position = position
        self.updatedAt = .now
        self.needsSync = true
    }

    var liveSets: [WorkoutSet] { sets.filter(\.isLive).sorted { $0.position < $1.position } }

    /// Last session's sets for this exercise.
    var previousSets: [WorkoutSet] { exercise?.lastSets(before: workout?.startedAt ?? .now) ?? [] }

    /// The weight and reps a set shows as placeholders: the same set last session, otherwise what the set above has
    /// (typed or shown). Ticking or finishing a set fills its blanks from these.
    func placeholder(at index: Int, in sets: [WorkoutSet], previous: [WorkoutSet]) -> (weight: Double?, reps: Int?) {
        if let last = previous[safe: index] { return (last.weight, last.reps) }
        guard index > 0, let above = sets[safe: index - 1] else { return (nil, nil) }
        let aboveHint = placeholder(at: index - 1, in: sets, previous: previous)
        return (above.weight ?? aboveHint.weight, above.reps ?? aboveHint.reps)
    }

    @discardableResult
    /// New sets start empty; the row shows last time's weight and reps as placeholders until you type or tick it.
    func addSet(unit: WeightUnit, context: ModelContext, template: WorkoutSet? = nil) -> WorkoutSet {
        let source = template ?? liveSets.last
        let set = WorkoutSet(
            position: (sets.map(\.position).max() ?? -1) + 1,
            setType: template?.setType ?? .working,
            unit: source?.unit ?? unit
        )
        context.insert(set)
        set.workoutExercise = self
        touch()
        return set
    }
}

@Model
final class WorkoutSet: SyncedModel {
    @Attribute(.unique) var id: UUID
    var workoutExercise: WorkoutExercise?
    var position: Int
    var setTypeRaw: String
    var weight: Double?
    var unitRaw: String
    var reps: Int?
    var rpe: Double?
    var notes: String?
    var completedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    init(
        id: UUID = UUID(), position: Int, setType: SetType = .working,
        weight: Double? = nil, unit: WeightUnit = .lb, reps: Int? = nil
    ) {
        self.id = id
        self.position = position
        self.setTypeRaw = setType.rawValue
        self.weight = weight
        self.unitRaw = unit.rawValue
        self.reps = reps
        self.updatedAt = .now
        self.needsSync = true
    }

    var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .working }
        set { setTypeRaw = newValue.rawValue }
    }

    var unit: WeightUnit {
        get { WeightUnit(rawValue: unitRaw) ?? .lb }
        set { unitRaw = newValue.rawValue }
    }
}

@Model
final class Routine: SyncedModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String?
    var position: Int
    /// Program id (e.g. "ppl", "custom-…") and day index when the routine belongs to a split.
    var program: String?
    var programDay: Int?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine) var items: [RoutineExercise] = []

    init(id: UUID = UUID(), name: String, position: Int = 0) {
        self.id = id
        self.name = name
        self.position = position
        self.updatedAt = .now
        self.needsSync = true
    }

    var liveItems: [RoutineExercise] { items.filter(\.isLive).sorted { $0.position < $1.position } }
}

@Model
final class RoutineExercise: SyncedModel {
    @Attribute(.unique) var id: UUID
    var routine: Routine?
    var exercise: Exercise?
    var position: Int
    var supersetGroup: Int?
    var targetSets: Int
    var repMin: Int?
    var repMax: Int?
    var restSeconds: Int?
    var notes: String?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    init(id: UUID = UUID(), position: Int, targetSets: Int = 3, repMin: Int? = 8, repMax: Int? = 12) {
        self.id = id
        self.position = position
        self.targetSets = targetSets
        self.repMin = repMin
        self.repMax = repMax
        self.updatedAt = .now
        self.needsSync = true
    }
}

@Model
final class BodyMetric: SyncedModel {
    @Attribute(.unique) var id: UUID
    var measuredAt: Date
    var bodyWeight: Double?
    var unitRaw: String
    var bodyFatPct: Double?
    var waistCm: Double?
    var neckCm: Double?
    var hipsCm: Double?
    var source: String
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    init(id: UUID = UUID(), measuredAt: Date = .now, bodyWeight: Double?, unit: WeightUnit = .lb) {
        self.id = id
        self.measuredAt = measuredAt
        self.bodyWeight = bodyWeight
        self.unitRaw = unit.rawValue
        self.source = "manual"
        self.updatedAt = .now
        self.needsSync = true
    }

    var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .lb }
}

@Model
final class FoodLog: SyncedModel {
    @Attribute(.unique) var id: UUID
    var eatenAt: Date
    var meal: String
    var source: String
    var place: String?
    var name: String
    var serving: String?
    var servings: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    init(id: UUID = UUID(), eatenAt: Date = .now, meal: String, source: String, place: String?, name: String,
         serving: String?, servings: Double = 1, kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.id = id
        self.eatenAt = eatenAt
        self.meal = meal
        self.source = source
        self.place = place
        self.name = name
        self.serving = serving
        self.servings = servings
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.updatedAt = .now
        self.needsSync = true
    }
}

extension Array where Element == BodyMetric {
    /// Body weight (in `unit`) when the latest body-fat % was logged: the last weigh-in up to a day after it, else the
    /// first one after. The body plan's goal and checkpoint are fixed from this weight. Mirrors planStartWeight on the web.
    func planStartWeight(in unit: WeightUnit) -> Double? {
        let live = filter { $0.deletedAt == nil }
        guard let bf = live.filter({ $0.bodyFatPct != nil }).max(by: { $0.measuredAt < $1.measuredAt }) else { return nil }
        let weights = live.filter { $0.bodyWeight != nil }.sorted { $0.measuredAt < $1.measuredAt }
        let cutoff = bf.measuredAt.addingTimeInterval(86_400)
        guard let entry = weights.last(where: { $0.measuredAt <= cutoff }) ?? weights.first(where: { $0.measuredAt > cutoff }),
              let weight = entry.bodyWeight else { return nil }
        return entry.unit.convert(weight, to: unit)
    }
}

enum WaterUnit: String, CaseIterable, Codable, Sendable {
    case oz, ml

    static let mlPerOz = 29.5735

    /// fl oz for lb users, ml for kg users.
    static func preferred(for unit: WeightUnit) -> WaterUnit { unit == .kg ? .ml : .oz }

    func convert(_ value: Double, to other: WaterUnit) -> Double {
        switch (self, other) {
        case (.oz, .ml): value * Self.mlPerOz
        case (.ml, .oz): value / Self.mlPerOz
        default: value
        }
    }

    /// Common cup and bottle sizes.
    var quickAmounts: [Double] { self == .oz ? [8, 16.9, 20, 32] : [250, 500, 750, 1000] }

    /// Daily goal in this unit: about 35 ml per kg of body weight, plus half a litre on days you train.
    func dailyGoal(bodyWeightKg: Double, trained: Bool) -> Double {
        let ml = bodyWeightKg * 35 + (trained ? 500 : 0)
        return WaterUnit.ml.convert(ml, to: self).rounded()
    }
}

/// Water drunk, stored as entered (fl oz or ml).
@Model
final class WaterLog: SyncedModel {
    @Attribute(.unique) var id: UUID
    var drankAt: Date
    var amount: Double
    var unitRaw: String
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    init(id: UUID = UUID(), drankAt: Date = .now, amount: Double, unit: WaterUnit) {
        self.id = id
        self.drankAt = drankAt
        self.amount = amount
        self.unitRaw = unit.rawValue
        self.updatedAt = .now
        self.needsSync = true
    }

    var unit: WaterUnit { WaterUnit(rawValue: unitRaw) ?? .oz }
}
