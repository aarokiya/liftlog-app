import Foundation
import HealthKit
import LiftKit
import Observation
import SwiftData

/// Apple Health: finished workouts go to Health as strength workouts; weight, body fat, waist, height,
/// daily nutrition totals (e.g. from MyFitnessPal) and daily steps come back.
@MainActor
@Observable
final class HealthService {
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()
    private let defaults = UserDefaults.standard
    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Prefs.healthEnabled) } }
    private(set) var lastError: String?
    private(set) var lastImportAt: Date?

    init() {
        isEnabled = defaults.bool(forKey: Prefs.healthEnabled)
    }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.bodyMass), HKQuantityType(.height), HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.waistCircumference), HKQuantityType(.leanBodyMass), HKObjectType.workoutType(),
            HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal), HKQuantityType(.stepCount),
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass)]
    }

    func enable() async {
        guard Self.isAvailable else {
            lastError = "Apple Health isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isEnabled = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Runs both directions; safe to call often.
    func sync(context: ModelContext) async {
        guard isEnabled, Self.isAvailable else { return }
        if !defaults.bool(forKey: Prefs.healthNutritionAsked) || !defaults.bool(forKey: Prefs.healthStepsAsked) {
            // Users who enabled Health before nutrition or steps were added get asked for the new types once.
            defaults.set(true, forKey: Prefs.healthNutritionAsked)
            defaults.set(true, forKey: Prefs.healthStepsAsked)
            try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        }
        await exportWorkouts(context: context)
        await importBody(context: context)
    }

    // MARK: Workouts → Health

    private func exportWorkouts(context: ModelContext) async {
        let pending = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate {
            $0.deletedAt == nil && $0.endedAt != nil && $0.healthExportedAt == nil && $0.source == "app"
        }))) ?? []
        guard !pending.isEmpty else { return }
        let bodyWeightKg = latestBodyWeightKg(context: context)
        for workout in pending {
            do {
                try await save(workout, bodyWeightKg: bodyWeightKg)
                workout.healthExportedAt = .now
            } catch {
                lastError = error.localizedDescription
                break
            }
        }
        try? context.save()
    }

    private func save(_ workout: Workout, bodyWeightKg: Double?) async throws {
        guard let end = workout.endedAt, end > workout.startedAt else { return }
        let exercises = workout.liveExercises.compactMap(\.exercise)
        let cardioOnly = !exercises.isEmpty && exercises.allSatisfy(\.isCardio)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = cardioOnly ? Self.cardioType(exercises) : .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: workout.startedAt)
        if let bodyWeightKg {
            // Health shows this as active energy: ~4 net METs for resistance training over the whole session, ~5 for
            // easy incline walking or stair climbing over the minutes logged.
            let loggedSeconds = workout.liveExercises.flatMap(\.liveSets).compactMap(\.durationSeconds).reduce(0, +)
            let kcal = cardioOnly && loggedSeconds > 0
                ? 5.0 * bodyWeightKg * Double(loggedSeconds) / 3600
                : 4.0 * bodyWeightKg * end.timeIntervalSince(workout.startedAt) / 3600
            try await builder.addSamples([
                HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: workout.startedAt, end: end
                ),
            ])
        }
        try await builder.addMetadata([HKMetadataKeyExternalUUID: workout.id.uuidString])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    /// Stair climbing or walking when that's all the session was, otherwise mixed cardio.
    private static func cardioType(_ exercises: [Exercise]) -> HKWorkoutActivityType {
        let ids = Set(exercises.map(\.id))
        if ids == Set([GymLibrary.builtInId(70)].compactMap { $0 }) { return .stairClimbing }
        if ids == Set([GymLibrary.builtInId(71)].compactMap { $0 }) { return .walking }
        return .mixedCardio
    }

    func saveBodyWeight(_ value: Double, unit: WeightUnit, at date: Date) async {
        guard isEnabled, Self.isAvailable else { return }
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: unit == .lb ? .pound() : .gramUnit(with: .kilo), doubleValue: value),
            start: date, end: date
        )
        do { try await store.save(sample) } catch { lastError = error.localizedDescription }
    }

    // MARK: Health → app

    struct Nutrition: Equatable {
        var kcal = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
    }

    /// Daily calories and macros other apps (MyFitnessPal, Lose It!, ...) wrote to Health from `start` up to `end`,
    /// keyed by the start of each day; empty if none or not allowed.
    func dailyNutrition(from start: Date, to end: Date) async -> [Date: Nutrition] {
        guard isEnabled, Self.isAvailable, end > start else { return [:] }
        let kcal = await daily(.dietaryEnergyConsumed, .kilocalorie(), from: start, to: end)
        let protein = await daily(.dietaryProtein, .gram(), from: start, to: end)
        let carbs = await daily(.dietaryCarbohydrates, .gram(), from: start, to: end)
        let fat = await daily(.dietaryFatTotal, .gram(), from: start, to: end)
        var result: [Date: Nutrition] = [:]
        for day in Set(kcal.keys).union(protein.keys).union(carbs.keys).union(fat.keys) {
            result[day] = Nutrition(kcal: kcal[day] ?? 0, protein: protein[day] ?? 0, carbs: carbs[day] ?? 0, fat: fat[day] ?? 0)
        }
        return result
    }

    /// Daily step counts from `start` up to `end`, keyed by the start of each day; empty if none or not allowed. Health
    /// merges the iPhone's and an Apple Watch's counts, so a step isn't counted twice. They stay on the phone.
    func dailySteps(from start: Date, to end: Date) async -> [Date: Double] {
        guard isEnabled, Self.isAvailable, end > start else { return [:] }
        return await daily(.stepCount, .count(), from: start, to: end)
    }

    /// A quantity's daily sums from the start of `start`'s day up to `end`, keyed by the start of each day; days with
    /// nothing are left out.
    private func daily(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from start: Date, to end: Date) async -> [Date: Double] {
        let from = Calendar.current.startOfDay(for: start)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: from, end: end)),
            options: .cumulativeSum, anchorDate: from, intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await query.result(for: store) else { return [:] }
        var values: [Date: Double] = [:]
        collection.enumerateStatistics(from: from, to: end) { statistics, _ in
            if let value = statistics.sumQuantity()?.doubleValue(for: unit), value > 0 { values[statistics.startDate] = value }
        }
        return values
    }

    private func importBody(context: ModelContext) async {
        let since = Calendar.current.date(byAdding: .year, value: -2, to: .now) ?? .distantPast
        let unit = WeightUnit(rawValue: defaults.string(forKey: Prefs.unit) ?? "") ?? .lb
        do {
            let existing = Set(((try? context.fetch(FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.source == "health" }))) ?? []).map(\.id))
            for sample in try await samples(.bodyMass, since: since) where !existing.contains(sample.uuid) {
                let metric = BodyMetric(
                    id: sample.uuid, measuredAt: sample.startDate,
                    bodyWeight: sample.quantity.doubleValue(for: unit == .lb ? .pound() : .gramUnit(with: .kilo)), unit: unit
                )
                metric.source = "health"
                context.insert(metric)
            }
            for sample in try await samples(.bodyFatPercentage, since: since) where !existing.contains(sample.uuid) {
                let metric = BodyMetric(id: sample.uuid, measuredAt: sample.startDate, bodyWeight: nil, unit: unit)
                metric.bodyFatPct = (sample.quantity.doubleValue(for: .percent()) * 1000).rounded() / 10
                metric.source = "health"
                context.insert(metric)
            }
            for sample in try await samples(.waistCircumference, since: since) where !existing.contains(sample.uuid) {
                let metric = BodyMetric(id: sample.uuid, measuredAt: sample.startDate, bodyWeight: nil, unit: unit)
                metric.waistCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                metric.source = "health"
                context.insert(metric)
            }
            if let height = try await samples(.height, since: .distantPast, limit: 1).first {
                // Health's height fills in a missing one or replaces it when Health has a newer measurement;
                // otherwise the height set in LiftLog or on the web wins.
                let cm = (height.quantity.doubleValue(for: .meterUnit(with: .centi)) * 10).rounded() / 10
                let seen = defaults.object(forKey: Prefs.healthHeightSeenAt) as? Date
                let missing = defaults.object(forKey: Prefs.heightCm) == nil
                let isNew = missing || (seen.map { height.startDate > $0 } ?? false)
                if isNew, defaults.object(forKey: Prefs.heightCm) as? Double != cm {
                    defaults.set(cm, forKey: Prefs.heightCm)
                    // Push only once this account's profile has been pulled, so a fresh install can't overwrite the web profile.
                    if defaults.bool(forKey: Prefs.profilePulled) { defaults.set(true, forKey: Prefs.profileNeedsSync) }
                }
                defaults.set(height.startDate, forKey: Prefs.healthHeightSeenAt)
            }
            try context.save()
            lastImportAt = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Samples from other apps and devices; LiftLog's own writes are skipped so they don't come back as duplicates.
    private func samples(_ id: HKQuantityTypeIdentifier, since: Date, limit: Int? = nil) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        let own = Bundle.main.bundleIdentifier
        return try await descriptor.result(for: store).filter { $0.sourceRevision.source.bundleIdentifier != own }
    }

    private func latestBodyWeightKg(context: ModelContext) -> Double? {
        var descriptor = FetchDescriptor<BodyMetric>(
            predicate: #Predicate { $0.deletedAt == nil && $0.bodyWeight != nil },
            sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first, let weight = latest.bodyWeight else { return nil }
        return latest.unit.convert(weight, to: .kg)
    }
}
