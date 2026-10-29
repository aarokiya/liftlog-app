import Foundation
import LiftKit

struct WeekVolume: Identifiable {
    let week: Date
    let volume: Double
    var id: Date { week }
}

struct MuscleCount: Identifiable {
    let muscle: String
    let sets: Double
    var id: String { muscle }
}

struct E1RMPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Stats derived from finished workouts, computed with LiftKit so they match the web dashboard.
struct TrainingData {
    let unit: WeightUnit
    let formula: OneRepMaxFormula
    let workouts: [Workout]
    let sets: [LiftSet]
    private let dates: [String: Date]

    init(workouts: [Workout], unit: WeightUnit, formula: OneRepMaxFormula) {
        self.unit = unit
        self.formula = formula
        self.workouts = workouts.sorted { $0.startedAt < $1.startedAt }
        sets = self.workouts.flatMap { $0.liftSets() }
        dates = Dictionary(self.workouts.map { ($0.id.uuidString, $0.startedAt) }, uniquingKeysWith: { a, _ in a })
    }

    var lifetimeVolume: Double { Volume.load(sets, unit: unit) }

    /// Lifting sessions this week; rest-day cardio doesn't count toward the target.
    var thisWeekCount: Int {
        let week = LocalDate(date: .now).weekNumber
        return workouts.filter { $0.hasLifting && LocalDate(date: $0.startedAt).weekNumber == week }.count
    }

    func streak(target: Int) -> Streaks.Result {
        Streaks.weekly(
            workoutDates: workouts.filter(\.hasLifting).map { LocalDate(date: $0.startedAt) },
            target: target,
            asOf: LocalDate(date: .now)
        )
    }

    func weeklyVolume(weeks: Int = 12) -> [WeekVolume] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        var totals: [Date: Double] = [:]
        for workout in workouts {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start else { continue }
            totals[start, default: 0] += Volume.load(workout.liftSets(), unit: unit)
        }
        return (0..<weeks).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek).map {
                WeekVolume(week: $0, volume: totals[$0] ?? 0)
            }
        }
    }

    func muscleSets(days: Int = 7, exercises: [Exercise]) -> [MuscleCount] {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let recent = workouts.filter { $0.startedAt >= cutoff }.flatMap { $0.liftSets(includingBodyweight: true) }
        let map = Dictionary(exercises.map { ($0.id.uuidString, $0.muscles) }, uniquingKeysWith: { a, _ in a })
        return MuscleSets.count(recent, exercises: map)
            .map { MuscleCount(muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets > $1.sets }
    }

    func sets(for exercise: Exercise) -> [LiftSet] {
        let id = exercise.id.uuidString
        return sets.filter { $0.exerciseId == id }
    }

    func e1rmSeries(for exercise: Exercise) -> [E1RMPoint] {
        OneRepMax.bestPerSession(sets(for: exercise), unit: unit, formula: formula)
            .compactMap { best in dates[best.sessionId].map { E1RMPoint(date: $0, value: best.value) } }
            .sorted { $0.date < $1.date }
    }
}

struct TrainingBalance {
    let ratios: Advanced.Balance
    let workload: Double?
    let density: Double?
    let recency: [(muscle: String, days: Int)]
    let bigThreeTotal: Double?
    let wilks: Double?
    let dots: Double?
}

extension TrainingData {
    /// Built-in Squat, Bench Press and Deadlift (Barbell) from supabase/seed.sql.
    static let bigThree = [
        "00000000-0000-4000-8000-000000000003",
        "00000000-0000-4000-8000-000000000001",
        "00000000-0000-4000-8000-000000000004",
    ]

    /// Wilks/DOTS need `sex`; they stay nil until it's set.
    func balance(exercises: [Exercise], bodyWeight: (value: Double, unit: WeightUnit)?, sex: Advanced.Sex?) -> TrainingBalance {
        let map = Dictionary(exercises.map { ($0.id.uuidString, $0.muscles) }, uniquingKeysWith: { a, _ in a })
        let today = LocalDate(date: .now).dayNumber
        let day = { (w: Workout) in LocalDate(date: w.startedAt).dayNumber }

        let recent = workouts.filter { day($0) > today - 28 }.flatMap { $0.liftSets(includingBodyweight: true) }
        let ratios = Advanced.balance(MuscleSets.count(recent, exercises: map))
        let workload = Advanced.acwr(workouts.map { (day: day($0), load: Volume.load($0.liftSets(), unit: unit)) }, today: today)

        // Sessions under 10 minutes (quick tests, back-filled logs) would give absurd rates.
        let densities = workouts.reversed().compactMap { w -> Double? in
            // Cardio-only sessions have no volume and would drag the average to zero.
            let volume = Volume.load(w.liftSets(), unit: unit)
            guard let end = w.endedAt, end.timeIntervalSince(w.startedAt) >= 600, volume > 0 else { return nil }
            return Advanced.density(volume: volume, minutes: end.timeIntervalSince(w.startedAt) / 60)
        }.prefix(10)
        let density = densities.isEmpty ? nil : (densities.reduce(0, +) / Double(densities.count)).rounded()

        var last: [String: Int] = [:]
        for w in workouts {
            for s in w.liftSets(includingBodyweight: true) where s.type.countsTowardStats {
                if let m = map[s.exerciseId]?.primary { last[m] = max(last[m] ?? .min, day(w)) }
            }
        }
        let recency = Advanced.muscleRecency(last, today: today).map { (muscle: $0.key, days: $0.value) }.sorted { $0.days > $1.days }

        let bests = Self.bigThree.map { id in
            OneRepMax.bestPerSession(sets.filter { $0.exerciseId == id }, unit: unit, formula: formula).map(\.value).max() ?? 0
        }
        let total = bests.allSatisfy { $0 > 0 } ? bests.reduce(0, +) : nil
        let totalKg = total.map { unit.convert($0, to: .kg) }
        let bodyKg = bodyWeight.map { $0.unit.convert($0.value, to: .kg) }
        let scores = sex.flatMap { sex in totalKg.flatMap { t in bodyKg.map { b in (Advanced.wilks(totalKg: t, bodyKg: b, sex: sex), Advanced.dots(totalKg: t, bodyKg: b, sex: sex)) } } }

        return TrainingBalance(ratios: ratios, workload: workload, density: density, recency: recency,
                               bigThreeTotal: total, wilks: scores?.0, dots: scores?.1)
    }
}

struct SessionPoint: Identifiable {
    let date: Date
    let e1rm: Double?
    let top: Double
    let volume: Double
    let reps: Int
    var id: Date { date }
}

struct ExerciseGrowth: Identifiable {
    let exercise: Exercise
    let points: [SessionPoint]
    let growth: Advanced.Growth
    var id: UUID { exercise.id }
}

extension TrainingData {
    /// One point per workout for an exercise, oldest first. Warmups are ignored.
    func sessions(for exercise: Exercise) -> [SessionPoint] {
        let id = exercise.id.uuidString
        return workouts.compactMap { workout in
            let list = workout.liftSets().filter { $0.exerciseId == id && $0.type.countsTowardStats }
            guard !list.isEmpty else { return nil }
            return SessionPoint(
                date: workout.startedAt,
                e1rm: OneRepMax.bestPerSession(list, unit: unit, formula: formula).first?.value,
                top: list.map { $0.unit.convert($0.weight, to: unit) }.max() ?? 0,
                volume: Volume.load(list, unit: unit),
                reps: list.reduce(0) { $0 + $1.reps }
            )
        }
    }

    /// e1RM growth per trained exercise within the last `days` (all time when nil), biggest gain first.
    func growth(exercises: [Exercise], days: Int?) -> [ExerciseGrowth] {
        let cutoff = days.map { LocalDate(date: .now).dayNumber - $0 }
        let rows: [ExerciseGrowth] = exercises.compactMap { exercise in
            let points = sessions(for: exercise).filter { p in cutoff.map { LocalDate(date: p.date).dayNumber > $0 } ?? true }
            let series = points.compactMap { p in p.e1rm.map { (day: Double(LocalDate(date: p.date).dayNumber), value: $0) } }
            guard let g = Advanced.growth(series) else { return nil }
            return ExerciseGrowth(exercise: exercise, points: points, growth: g)
        }
        return rows.sorted { ($0.growth.changePct ?? -.infinity) > ($1.growth.changePct ?? -.infinity) }
    }
}
