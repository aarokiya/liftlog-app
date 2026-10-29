import Foundation
import Observation
import Supabase
import SwiftData

/// Offline-first sync: push rows flagged `needsSync`, then pull rows changed on the server since the
/// last cursor. Conflicts resolve last-write-wins per row.
@MainActor
@Observable
final class SyncService {
    private static let pageSize = 1000
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?

    func run(context: ModelContext, auth: AuthService) async {
        guard !isSyncing, let client = auth.client, let userId = auth.userId else { return }
        isSyncing = true
        defer { isSyncing = false }
        let pass = SyncPass(client: client, context: context, userId: userId)
        var failure: String?
        // Pull even when a push fails, so one row the server rejects can't stop changes from arriving.
        do { try await pass.push() } catch { failure = error.localizedDescription }
        do {
            try await pass.pull()
            try context.save()
        } catch {
            failure = failure ?? error.localizedDescription
        }
        failure = failure ?? pass.failures.first
        if failure == nil { lastSyncedAt = .now }
        lastError = failure
    }

    /// Per-table push errors; the rows stay flagged and are retried next sync.
    @MainActor
    private final class Failures {
        var messages: [String] = []
        var first: String? { messages.first }
    }

    @MainActor
    private struct SyncPass {
        let client: SupabaseClient
        let context: ModelContext
        let userId: UUID
        let defaults = UserDefaults.standard
        let failures = Failures()

        // MARK: Push

        func push() async throws {
            try await pushProfile()
            try await push("exercises", try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.needsSync && !$0.isBuiltIn }))) { e in
                ExerciseRow(
                    id: e.id, user_id: userId, name: e.name, kind: e.kind, equipment: .init(e.equipment),
                    primary_muscle: e.primaryMuscle, secondary_muscles: e.secondaryMuscles,
                    default_rest_seconds: e.defaultRestSeconds, sticky_note: .init(e.stickyNote), deleted_at: .init(e.deletedAt)
                )
            }
            try await push("routines", try context.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.needsSync }))) { r in
                RoutineRow(
                    id: r.id, user_id: userId, name: r.name, notes: .init(r.notes), position: r.position,
                    program: .init(r.program), program_day: .init(r.programDay), deleted_at: .init(r.deletedAt)
                )
            }
            try await push("routine_exercises", try context.fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.needsSync }))) { (x: RoutineExercise) -> RoutineExerciseRow? in
                guard let routine = x.routine, let exercise = x.exercise else { return nil }
                return RoutineExerciseRow(
                    id: x.id, user_id: userId, routine_id: routine.id, exercise_id: exercise.id, position: x.position,
                    superset_group: .init(x.supersetGroup), target_sets: x.targetSets, rep_min: .init(x.repMin),
                    rep_max: .init(x.repMax), rest_seconds: .init(x.restSeconds), notes: .init(x.notes), deleted_at: .init(x.deletedAt)
                )
            }
            try await push("workouts", try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.needsSync }))) { w in
                WorkoutRow(
                    id: w.id, user_id: userId, routine_id: .init(w.routineId), name: w.name, notes: .init(w.notes),
                    started_at: w.startedAt, ended_at: .init(w.endedAt), timezone: w.timezone, source: w.source,
                    deleted_at: .init(w.deletedAt)
                )
            }
            try await push("workout_exercises", try context.fetch(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.needsSync }))) { (x: WorkoutExercise) -> WorkoutExerciseRow? in
                guard let workout = x.workout, let exercise = x.exercise else { return nil }
                return WorkoutExerciseRow(
                    id: x.id, user_id: userId, workout_id: workout.id, exercise_id: exercise.id, position: x.position,
                    superset_group: .init(x.supersetGroup), notes: .init(x.notes), deleted_at: .init(x.deletedAt)
                )
            }
            try await push("sets", try context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.needsSync }))) { (s: WorkoutSet) -> SetRow? in
                guard let parent = s.workoutExercise else { return nil }
                return SetRow(
                    id: s.id, user_id: userId, workout_exercise_id: parent.id, position: s.position, set_type: s.setTypeRaw,
                    weight: .init(s.weight), weight_unit: s.unitRaw, reps: .init(s.reps), duration_seconds: .init(s.durationSeconds), rpe: .init(s.rpe),
                    notes: .init(s.notes), completed_at: .init(s.completedAt), deleted_at: .init(s.deletedAt)
                )
            }
            try await push("body_metrics", try context.fetch(FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.needsSync }))) { b in
                BodyMetricRow(
                    id: b.id, user_id: userId, measured_at: b.measuredAt, body_weight: .init(b.bodyWeight), unit: b.unitRaw,
                    body_fat_pct: .init(b.bodyFatPct), waist_cm: .init(b.waistCm), neck_cm: .init(b.neckCm), hips_cm: .init(b.hipsCm),
                    source: b.source, deleted_at: .init(b.deletedAt)
                )
            }
            try await push("food_logs", try context.fetch(FetchDescriptor<FoodLog>(predicate: #Predicate { $0.needsSync }))) { f in
                FoodLogRow(
                    id: f.id, user_id: userId, eaten_at: f.eatenAt, meal: f.meal, source: f.source, place: .init(f.place),
                    name: f.name, serving: .init(f.serving), servings: f.servings, kcal: f.kcal, protein: f.protein,
                    carbs: f.carbs, fat: f.fat, deleted_at: .init(f.deletedAt)
                )
            }
            try await push("water_logs", try context.fetch(FetchDescriptor<WaterLog>(predicate: #Predicate { $0.needsSync }))) { w in
                WaterLogRow(id: w.id, user_id: userId, drank_at: w.drankAt, amount: w.amount, unit: w.unitRaw, deleted_at: .init(w.deletedAt))
            }
        }

        private func push<M: SyncedModel, R: Encodable & Sendable>(_ table: String, _ models: [M], _ map: (M) -> R?) async throws {
            for start in stride(from: 0, to: models.count, by: 500) {
                let chunk = models[start..<min(start + 500, models.count)]
                let pending = chunk.compactMap { model in map(model).map { (model: model, stamp: model.updatedAt, row: $0) } }
                guard !pending.isEmpty else { continue }
                do {
                    try await client.from(table).upsert(pending.map(\.row)).execute()
                } catch {
                    // Leave these rows flagged and move on to the next table.
                    failures.messages.append("\(table): \(error.localizedDescription)")
                    return
                }
                for item in pending where item.model.updatedAt == item.stamp {
                    item.model.needsSync = false
                }
            }
        }

        private func pushProfile() async throws {
            guard defaults.bool(forKey: Prefs.profileNeedsSync) else { return }
            let row = ProfileRow(
                id: userId,
                display_name: .init(defaults.string(forKey: Prefs.displayName)),
                default_unit: defaults.string(forKey: Prefs.unit) ?? "lb",
                e1rm_formula: defaults.string(forKey: Prefs.formula) ?? "epley",
                weekly_workout_target: defaults.object(forKey: Prefs.weeklyTarget) as? Int ?? 3,
                bar_weight: defaults.object(forKey: Prefs.barWeight) as? Double ?? 45,
                height_cm: .init(defaults.object(forKey: Prefs.heightCm) as? Double),
                active_program: .init(defaults.string(forKey: Prefs.activeProgram)),
                campus: .init(defaults.string(forKey: Prefs.campus).flatMap { $0.isEmpty ? nil : $0 }),
                sex: .init(defaults.string(forKey: Prefs.sex).flatMap { $0.isEmpty ? nil : $0 })
            )
            try await client.from("profiles").update(row).eq("id", value: userId).execute()
            defaults.set(false, forKey: Prefs.profileNeedsSync)
        }

        // MARK: Pull

        func pull() async throws {
            try await pullProfile()
            try await pull("exercises", as: ExerciseRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { ids.contains($0.id) })))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    let e = existing[row.id] ?? insert(Exercise(id: row.id, name: row.name, primaryMuscle: row.primary_muscle))
                    e.isBuiltIn = row.user_id == nil
                    e.name = row.name
                    e.kind = row.kind
                    e.equipment = row.equipment.value
                    e.primaryMuscle = row.primary_muscle
                    e.secondaryMuscles = row.secondary_muscles
                    e.defaultRestSeconds = row.default_rest_seconds
                    e.stickyNote = row.sticky_note.value
                    applied(e, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("routines", as: RoutineRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<Routine>(predicate: #Predicate { ids.contains($0.id) })))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    let r = existing[row.id] ?? insert(Routine(id: row.id, name: row.name))
                    r.name = row.name
                    r.notes = row.notes.value
                    r.position = row.position
                    r.program = row.program.value
                    r.programDay = row.program_day.value
                    applied(r, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("routine_exercises", as: RoutineExerciseRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { ids.contains($0.id) })))
                let routines = try lookup(Routine.self, rows.map(\.routine_id))
                let exercises = try lookup(Exercise.self, rows.map(\.exercise_id))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    guard let routine = routines[row.routine_id], let exercise = exercises[row.exercise_id] else { continue }
                    let x = existing[row.id] ?? insert(RoutineExercise(id: row.id, position: row.position))
                    x.routine = routine
                    x.exercise = exercise
                    x.position = row.position
                    x.supersetGroup = row.superset_group.value
                    x.targetSets = row.target_sets
                    x.repMin = row.rep_min.value
                    x.repMax = row.rep_max.value
                    x.restSeconds = row.rest_seconds.value
                    x.notes = row.notes.value
                    applied(x, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("workouts", as: WorkoutRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { ids.contains($0.id) })))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    let w = existing[row.id] ?? insert(Workout(id: row.id, name: row.name, startedAt: row.started_at))
                    w.routineId = row.routine_id.value
                    w.name = row.name
                    w.notes = row.notes.value
                    w.startedAt = row.started_at
                    w.endedAt = row.ended_at.value
                    w.timezone = row.timezone
                    w.source = row.source
                    applied(w, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("workout_exercises", as: WorkoutExerciseRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { ids.contains($0.id) })))
                let workouts = try lookup(Workout.self, rows.map(\.workout_id))
                let exercises = try lookup(Exercise.self, rows.map(\.exercise_id))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    guard let workout = workouts[row.workout_id], let exercise = exercises[row.exercise_id] else { continue }
                    let x = existing[row.id] ?? insert(WorkoutExercise(id: row.id, position: row.position))
                    x.workout = workout
                    x.exercise = exercise
                    x.position = row.position
                    x.supersetGroup = row.superset_group.value
                    x.notes = row.notes.value
                    applied(x, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("sets", as: SetRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { ids.contains($0.id) })))
                let parents = try lookup(WorkoutExercise.self, rows.map(\.workout_exercise_id))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    guard let parent = parents[row.workout_exercise_id] else { continue }
                    let s = existing[row.id] ?? insert(WorkoutSet(id: row.id, position: row.position))
                    s.workoutExercise = parent
                    s.position = row.position
                    s.setTypeRaw = row.set_type
                    s.weight = row.weight.value
                    s.unitRaw = row.weight_unit
                    s.reps = row.reps.value
                    s.durationSeconds = row.duration_seconds.value
                    s.rpe = row.rpe.value
                    s.notes = row.notes.value
                    s.completedAt = row.completed_at.value
                    applied(s, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("body_metrics", as: BodyMetricRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<BodyMetric>(predicate: #Predicate { ids.contains($0.id) })))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    let b = existing[row.id] ?? insert(BodyMetric(id: row.id, measuredAt: row.measured_at, bodyWeight: nil))
                    b.measuredAt = row.measured_at
                    b.bodyWeight = row.body_weight.value
                    b.unitRaw = row.unit
                    b.bodyFatPct = row.body_fat_pct.value
                    b.waistCm = row.waist_cm.value
                    b.neckCm = row.neck_cm.value
                    b.hipsCm = row.hips_cm.value
                    b.source = row.source
                    applied(b, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("food_logs", as: FoodLogRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<FoodLog>(predicate: #Predicate { ids.contains($0.id) })))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    let f = existing[row.id] ?? insert(FoodLog(
                        id: row.id, meal: row.meal, source: row.source, place: nil, name: row.name, serving: nil,
                        kcal: 0, protein: 0, carbs: 0, fat: 0
                    ))
                    f.eatenAt = row.eaten_at
                    f.meal = row.meal
                    f.source = row.source
                    f.place = row.place.value
                    f.name = row.name
                    f.serving = row.serving.value
                    f.servings = row.servings
                    f.kcal = row.kcal
                    f.protein = row.protein
                    f.carbs = row.carbs
                    f.fat = row.fat
                    applied(f, row, deletedAt: row.deleted_at.value)
                }
            }
            try await pull("water_logs", as: WaterLogRow.self) { rows in
                let ids = rows.map(\.id)
                let existing = index(try context.fetch(FetchDescriptor<WaterLog>(predicate: #Predicate { ids.contains($0.id) })))
                for row in rows where shouldApply(existing[row.id], row.updated_at) {
                    let w = existing[row.id] ?? insert(WaterLog(id: row.id, amount: row.amount, unit: WaterUnit(rawValue: row.unit) ?? .oz))
                    w.drankAt = row.drank_at
                    w.amount = row.amount
                    w.unitRaw = row.unit
                    applied(w, row, deletedAt: row.deleted_at.value)
                }
            }
        }

        private func pull<R: RemoteRow>(_ table: String, as _: R.Type, apply: ([R]) throws -> Void) async throws {
            let key = "sync.cursor.\(userId.uuidString).\(table)"
            var cursor = defaults.object(forKey: key) as? Date ?? Date(timeIntervalSince1970: 0)
            while true {
                let rows: [R] = try await client.from(table)
                    .select()
                    .gt("updated_at", value: SyncService.iso.string(from: cursor))
                    .order("updated_at")
                    .limit(SyncService.pageSize)
                    .execute()
                    .value
                try apply(rows)
                try context.save()
                if let last = rows.last?.updated_at {
                    cursor = last
                    defaults.set(cursor, forKey: key)
                }
                if rows.count < SyncService.pageSize { break }
            }
        }

        private func pullProfile() async throws {
            guard !defaults.bool(forKey: Prefs.profileNeedsSync) else { return }
            let rows: [ProfileRow] = try await client.from("profiles").select().eq("id", value: userId).execute().value
            guard let profile = rows.first else { return }
            defaults.set(profile.display_name.value, forKey: Prefs.displayName)
            defaults.set(profile.default_unit, forKey: Prefs.unit)
            defaults.set(profile.e1rm_formula, forKey: Prefs.formula)
            defaults.set(profile.weekly_workout_target, forKey: Prefs.weeklyTarget)
            defaults.set(profile.bar_weight, forKey: Prefs.barWeight)
            defaults.set(profile.height_cm.value, forKey: Prefs.heightCm)
            defaults.set(profile.active_program.value, forKey: Prefs.activeProgram)
            defaults.set(profile.campus.value ?? "", forKey: Prefs.campus)
            defaults.set(profile.sex.value ?? "", forKey: Prefs.sex)
            defaults.set(true, forKey: Prefs.profilePulled)
        }

        // MARK: Helpers

        private func insert<M: PersistentModel>(_ model: M) -> M {
            context.insert(model)
            return model
        }

        private func index<M: SyncedModel>(_ models: [M]) -> [UUID: M] {
            Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }

        private func lookup<M: SyncedModel & PersistentModel>(_: M.Type, _ ids: [UUID]) throws -> [UUID: M] {
            let wanted = Set(ids)
            // Fetch by type with a concrete predicate; SwiftData can't build #Predicate over a generic.
            let models: [M]
            switch M.self {
            case is Routine.Type:
                models = try context.fetch(FetchDescriptor<Routine>(predicate: #Predicate { wanted.contains($0.id) })) as! [M]
            case is Exercise.Type:
                models = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { wanted.contains($0.id) })) as! [M]
            case is Workout.Type:
                models = try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { wanted.contains($0.id) })) as! [M]
            case is WorkoutExercise.Type:
                models = try context.fetch(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { wanted.contains($0.id) })) as! [M]
            default:
                models = []
            }
            return index(models)
        }

        /// Server wins unless the local row has unpushed edits newer than the server copy.
        private func shouldApply(_ local: (any SyncedModel)?, _ remoteUpdatedAt: Date?) -> Bool {
            guard let local else { return true }
            return !local.needsSync || (remoteUpdatedAt ?? .distantPast) > local.updatedAt
        }

        private func applied(_ model: any SyncedModel, _ row: any RemoteRow, deletedAt: Date?) {
            model.deletedAt = deletedAt
            model.updatedAt = row.updated_at ?? .now
            model.needsSync = false
        }
    }
}
