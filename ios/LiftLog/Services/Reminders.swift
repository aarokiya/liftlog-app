import Foundation
import LiftKit
import Observation
import SwiftData
import UserNotifications

/// Daily reminders as local notifications (free signing has no push): check-ins at 10am, 1pm and 8pm, and at 10pm an
/// alert for each of the day's food and water goals not hit yet. A notification's text is fixed when it's scheduled, so
/// each refresh replaces them all with one-shot requests for today and the next 6 days, built from what's logged in
/// LiftLog and Apple Health at that moment. Every id starts with `prefix`, so the rest timer's is never touched.
@MainActor
@Observable
final class Reminders: NSObject {
    nonisolated static let prefix = "reminder-"
    /// Set when a reminder is tapped; RootView switches to the Food tab and clears it.
    var openFood = false
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// The last Health totals used and the day they were read, for refreshes that don't read Health again.
    @ObservationIgnored private var healthCache: (day: Date, days: [Date: HealthService.Nutrition])?

    private var isOn: Bool { UserDefaults.standard.bool(forKey: Prefs.reminders) }

    /// Asks to show alerts with sound; false when notifications are denied.
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    var isDenied: Bool {
        get async { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied }
    }

    /// Rebuilds every reminder; does nothing while they're off. `healthDays` are Health totals the caller already has
    /// (the Food screen's, from 33+ days back). Without them Health is read again, unless `rereadHealth` is false and
    /// it was read today: going to the background, the phone may be locking.
    func refresh(context: ModelContext, health: HealthService, healthDays: [Date: HealthService.Nutrition]? = nil,
                 rereadHealth: Bool = true) {
        guard isOn else { return }
        enqueue { [weak self] in
            guard let self else { return }
            let now = Date.now
            let today = Calendar.current.startOfDay(for: now)
            let days: [Date: HealthService.Nutrition]
            if let healthDays {
                days = healthDays
            } else if !rereadHealth, let cache = healthCache, cache.day == today {
                days = cache.days
            } else {
                days = await health.dailyNutrition(from: EnergyTargets.historyStart(now) ?? today, to: now)
            }
            healthCache = (today, days)
            guard !Task.isCancelled, isOn else { return }
            await Self.replace(with: Self.notes(for: Self.status(context: context, healthDays: days, now: now), now: now))
        }
    }

    /// Removes every pending reminder.
    func removeAll() {
        enqueue { await Self.replace(with: []) }
    }

    /// Runs `work` once the previous refresh has stopped; that one is cancelled, so two never interleave.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        previous?.cancel()
        queue = Task {
            await previous?.value
            await work()
        }
    }

    /// Swaps the pending reminders for `notes`, unless a newer refresh has started.
    private static func replace(with notes: [Note]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for note in notes {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            content.threadIdentifier = "reminders"
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: note.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: trigger))
        }
    }

    // MARK: Status

    /// What the reminders say: today's totals and goals so far, and the plan for the days ahead.
    struct Status {
        var today: DayGoals
        /// The plan's targets before carryover; nil without a plan.
        var base: Energy.Targets?
        /// The water goal on a day without a workout; nil without a logged body weight.
        var waterGoal: Double?
        var waterUnit: WaterUnit
    }

    /// Today as the Food screen and its goals calendar compute it, from the database and Health totals keyed by start
    /// of day, so it works without the Food screen having been opened.
    static func status(context: ModelContext, healthDays: [Date: HealthService.Nutrition], now: Date) -> Status {
        let today = Calendar.current.startOfDay(for: now)
        let start = EnergyTargets.historyStart(now) ?? today
        let defaults = UserDefaults.standard
        let unit = WeightUnit(rawValue: defaults.string(forKey: Prefs.unit) ?? "") ?? .lb
        let waterUnit = WaterUnit.preferred(for: unit)
        let logs = (try? context.fetch(FetchDescriptor<FoodLog>(predicate: #Predicate { $0.deletedAt == nil && $0.eatenAt >= start }))) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterLog>(predicate: #Predicate { $0.deletedAt == nil && $0.drankAt >= today }))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= today }))) ?? []
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]))) ?? []
        let energy = EnergyTargets(metrics: metrics, logs: logs, health: healthDays, sex: Advanced.Sex(pref: defaults.string(forKey: Prefs.sex) ?? ""),
                                   unit: unit, from: start, now: now)
        let goals = DayGoals.byDay([today], logs: logs, waterLogs: water, workouts: workouts, metrics: metrics, waterUnit: waterUnit,
                                   healthDays: healthDays, targets: energy)
        let weight = metrics.first { $0.deletedAt == nil && $0.bodyWeight != nil }
        return Status(
            today: goals[today] ?? DayGoals(), base: energy?.base.targets,
            waterGoal: weight.flatMap { entry in entry.bodyWeight.map { waterUnit.dailyGoal(bodyWeightKg: entry.unit.convert($0, to: .kg), trained: false) } },
            waterUnit: waterUnit
        )
    }

    // MARK: Content

    struct Note: Equatable {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    private struct Message {
        let hour: Int
        /// Tells a day's notifications apart in the id.
        let key: String
        let title: String
        let body: String
    }

    /// The check-ins and 10pm alerts for the times still ahead today and for the next 6 days. Today's use its numbers
    /// so far; the days ahead only know the plan.
    static func notes(for status: Status, now: Date, calendar: Calendar = .current) -> [Note] {
        let start = calendar.startOfDay(for: now)
        var notes: [Note] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let d = calendar.dateComponents([.year, .month, .day], from: day)
            let stamp = String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
            for message in offset == 0 ? today(status) : ahead(status) {
                guard let date = calendar.date(bySettingHour: message.hour, minute: 0, second: 0, of: day), date > now else { continue }
                notes.append(Note(id: "\(prefix)\(stamp)-\(message.key)", date: date, title: message.title, body: message.body))
            }
        }
        return notes
    }

    private static func today(_ status: Status) -> [Message] {
        let goals = status.today
        let unit = status.waterUnit.rawValue
        guard goals.targets != nil || goals.waterGoal != nil else { return checkIns(hasGoals: false) + (goals.hasData ? [] : [nothingLogged]) }
        let kcal = Int(goals.kcal.rounded()), protein = Int(goals.protein.rounded()), water = goals.water.rounded()

        let planned = [goals.targets.map { "\($0.kcal.formatted()) kcal" }, goals.targets.map { "\($0.protein.formatted()) g protein" },
                       goals.waterGoal.map { "\(Format.number($0)) \(unit) water" }].compactMap { $0 }
        let soFar = [goals.targets.map { "\(kcal.formatted()) / \($0.kcal.formatted()) kcal" },
                     goals.targets.map { "\(protein.formatted()) / \($0.protein.formatted()) g protein" },
                     goals.waterGoal.map { "\(Format.number(goals.water)) / \(Format.number($0)) \(unit) water" }].compactMap { $0 }
        var left: [String] = []
        if let t = goals.targets {
            if goals.proteinState == .hit, goals.waterState == .hit { left.append("Protein and water goals hit") }
            if t.protein > protein { left.append("\((t.protein - protein).formatted()) g protein to go") }
            left.append(t.kcal >= kcal ? "\((t.kcal - kcal).formatted()) kcal left" : "\((kcal - t.kcal).formatted()) kcal over")
        } else if goals.waterState == .hit {
            left.append("Water goal hit")
        }
        if let goal = goals.waterGoal, goal > water { left.append("\(Format.number(goal - water)) \(unit) water to go") }

        var messages = [
            Message(hour: 10, key: "10", title: "Today's goals", body: planned.joined(separator: " · ") + ". Log breakfast and a drink."),
            Message(hour: 13, key: "13", title: "Midday check-in", body: soFar.joined(separator: " · ") + " so far. Log lunch."),
            Message(hour: 20, key: "20", title: "Evening check-in", body: left.joined(separator: " · ") + "."),
        ]
        guard goals.hasData else { return messages + [nothingLogged] }
        if let t = goals.targets, goals.proteinState != .hit {
            messages.append(Message(hour: 22, key: "22-protein", title: "Protein goal", body: "\((t.protein - protein).formatted()) g protein to go today."))
        }
        if let goal = goals.waterGoal, goals.waterState != .hit {
            messages.append(Message(hour: 22, key: "22-water", title: "Water goal", body: "\(Format.number(goal - water)) \(unit) to go today."))
        }
        // Over is left alone: nothing helps at 10pm, and carryover already lowers tomorrow's target.
        if let t = goals.targets, goals.kcalState != .hit, kcal < t.kcal {
            // Carryover only counts days logged to at least half the target (Energy.daily).
            let next = goals.kcal >= 0.5 * Double(t.kcal) ? "Finish under and tomorrow's target goes up a little." : "Log anything you missed."
            messages.append(Message(hour: 22, key: "22-kcal", title: "Calorie goal",
                                    body: "\((t.kcal - kcal).formatted()) kcal under today's \(t.kcal.formatted()) kcal target. \(next)"))
        }
        return messages
    }

    /// Days ahead: the plan's targets before carryover, which can move calories a little, and no progress. Their 10pm
    /// alert is generic until a refresh on the day replaces it.
    private static func ahead(_ status: Status) -> [Message] {
        let hasGoals = status.base != nil || status.waterGoal != nil
        var messages = checkIns(hasGoals: hasGoals)
        if hasGoals {
            let planned = [status.base.map { "about \($0.kcal.formatted()) kcal" }, status.base.map { "\($0.protein.formatted()) g protein" },
                           status.waterGoal.map { "\(Format.number($0))+ \(status.waterUnit.rawValue) water" }].compactMap { $0 }.joined(separator: " · ")
            messages[0] = Message(hour: 10, key: "10", title: "Today's goals",
                                  body: planned.prefix(1).uppercased() + String(planned.dropFirst()) + ". Log breakfast and a drink.")
        }
        messages.append(hasGoals
            ? Message(hour: 22, key: "22", title: "Today's goals", body: "Open LiftLog to check which goals are left before the day ends.")
            : Message(hour: 22, key: "22", title: "Today's log", body: "Log the rest of today's food and water."))
        return messages
    }

    /// Check-ins without numbers, for days ahead and for today without goals.
    private static func checkIns(hasGoals: Bool) -> [Message] {
        [
            Message(hour: 10, key: "10", title: "Good morning", body: "Log breakfast and a drink in LiftLog."),
            Message(hour: 13, key: "13", title: "Midday check-in", body: hasGoals ? "Log lunch, then see how today's goals are going." : "Log lunch in LiftLog."),
            Message(hour: 20, key: "20", title: "Evening check-in",
                    body: hasGoals ? "Log dinner and see what's left of today's goals." : "Log dinner and anything else you had today."),
        ]
    }

    private static let nothingLogged = Message(hour: 22, key: "22-nothing", title: "Nothing logged today",
                                               body: "Log today's meals and water in LiftLog before bed.")
}

extension Reminders: UNUserNotificationCenterDelegate {
    /// Shows reminders as banners while the app is open; anything else (the rest timer) stays hidden, as without a delegate.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier.hasPrefix(Self.prefix) ? [.banner, .list, .sound] : [])
    }

    /// Tapping a reminder opens the Food tab.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(Self.prefix) {
            Task { @MainActor in self.openFood = true }
        }
        completionHandler()
    }
}
