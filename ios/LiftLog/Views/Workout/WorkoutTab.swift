import LiftKit
import SwiftData
import SwiftUI

struct WorkoutTab: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @Query(filter: Workout.inProgress, sort: \Workout.startedAt, order: .reverse)
    private var active: [Workout]
    @Query(filter: #Predicate<Routine> { $0.deletedAt == nil }, sort: \Routine.position)
    private var routines: [Routine]
    @AppStorage(Prefs.activeProgram) private var activeProgram: String?
    /// The rest day whose cardio choices are showing.
    @State private var restDay: Routine?
    /// The day tapped in the strip; nil shows up next.
    @State private var picked: UUID?

    /// The active program's days, then the user's own routines; days of programs switched away from stay in the Routines tab.
    private var startable: [Routine] {
        let list = ProgramLibrary.days(of: activeProgram, in: routines) + routines.filter { $0.program == nil }
        return list.isEmpty ? routines : list
    }

    var body: some View {
        NavigationStack {
            if let workout = active.first {
                WorkoutEditor(workout: workout, isActive: true)
            } else {
                List {
                    // The strip holds the program's days; without a program, the routines it would have listed.
                    let program = ProgramLibrary.days(of: activeProgram, in: routines)
                    let days = program.isEmpty ? startable : program
                    let others = startable.filter { routine in !days.contains { $0.id == routine.id } }
                    let upNext = ProgramLibrary.upNext(in: program, context: context)
                    let selected = days.first { $0.id == picked } ?? upNext ?? days.first
                    Section {
                        if let selected {
                            WeekStrip(days: days, isProgram: !program.isEmpty, selected: selected, upNext: upNext) { picked = $0.id }
                                .listRowInsets(EdgeInsets(top: 10, leading: 6, bottom: 8, trailing: 6))
                            DayPlan(routine: selected, day: dayLabel(selected, in: program)) {
                                if selected.isRestDay { restDay = selected } else { start(selected) }
                            }
                            .id(selected.id)
                        } else {
                            Text("Pick a ready-made program in Routines → Programs, or create your own routine there.").foregroundStyle(.secondary)
                        }
                    } footer: {
                        // Other routines and an empty workout stay one tap away, but quiet.
                        HStack {
                            if !others.isEmpty {
                                Menu("Other routines") {
                                    ForEach(others) { routine in
                                        Button(routine.name) {
                                            if routine.isRestDay { restDay = routine } else { start(routine) }
                                        }
                                    }
                                }
                            }
                            Spacer()
                            Button("Empty workout") { start(nil) }
                        }
                        .font(.footnote)
                        .textCase(nil)
                    }
                    WorkoutHistorySections()
                }
                .navigationTitle("Workout")
            }
        }
        .sheet(item: $restDay) { RestDaySheet(routine: $0) }
        // After a workout, the strip goes back to what's up next.
        .onChange(of: active.first?.id) { picked = nil }
    }

    /// "Mon" for a day of a 7-day program, "Day 2" in a rotation of another length, nothing outside a program.
    private func dayLabel(_ routine: Routine, in program: [Routine]) -> String? {
        guard let index = program.firstIndex(where: { $0.id == routine.id }) else { return nil }
        return program.count == 7 ? WeekStrip.weekdayName(index) : "Day \(index + 1)"
    }

    private func start(_ routine: Routine?) {
        _ = Workout.start(routine: routine, unit: WeightUnit(rawValue: unitRaw) ?? .lb, context: context)
        try? context.save()
    }
}

/// An accent colour per kind of day, picked from the routine's name.
struct RoutineStyle {
    let color: Color

    init(name: String) {
        let n = name.lowercased()
        color = switch true {
        case n.contains("rest"), n.contains("cardio"): .mint
        case n.contains("push"): .orange
        case n.contains("pull"): .teal
        case n.contains("leg"): .green
        case n.contains("upper"): .purple
        case n.contains("lower"): .indigo
        case n.contains("delt"), n.contains("arm"), n.contains("shoulder"): .pink
        case n.contains("chest"), n.contains("back"): .red
        default: .gray
        }
    }
}

/// The picked day: its name and weekday, "7 exercises · ~55 min", the exercises with their target sets, and Start.
struct DayPlan: View {
    let routine: Routine
    /// "Mon" or "Day 2".
    let day: String?
    var start: () -> Void
    @State private var showingAll = false

    /// Up to this many exercises show in full; longer days show one less and "+N more".
    private static let visible = 7

    /// A rough length: each set takes about 45 s of work plus the exercise's rest (120 s when it has none), rounded to
    /// 5 minutes. Warm-ups and walking between machines aren't counted.
    static func minutes(_ items: [RoutineExercise]) -> Int {
        let seconds = items.reduce(0) { total, item in
            total + item.targetSets * ((item.restSeconds ?? item.exercise?.defaultRestSeconds ?? 120) + 45)
        }
        return max(5, Int((Double(seconds) / 300).rounded()) * 5)
    }

    var body: some View {
        let items = routine.liveItems
        let shown = showingAll || items.count <= Self.visible ? items : Array(items.prefix(Self.visible - 1))
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(routine.name).font(.title2.bold())
                    Spacer()
                    if let day { Text(day).font(.subheadline).foregroundStyle(.secondary) }
                }
                Text(routine.isRestDay
                     ? "Rest, or light zone-2 cardio"
                     : "\(items.count) exercise\(items.count == 1 ? "" : "s") · ~\(Self.minutes(items)) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(shown) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.exercise?.name ?? "Exercise")
                            Spacer()
                            if !routine.isRestDay {
                                Text("\(item.targetSets)×").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    if shown.count < items.count {
                        Button("+\(items.count - shown.count) more") { showingAll = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            Button(action: start) {
                Text(routine.isRestDay ? "Start cardio" : "Start").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }
}
