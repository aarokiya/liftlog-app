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
                    Section {
                        Button {
                            start(nil)
                        } label: {
                            StartRow(title: "Start empty workout", detail: "Add exercises as you go", symbol: "plus", colors: [Color(.systemGray2), Color(.systemGray)])
                        }
                        .buttonStyle(.plain)
                    }
                    Section("Start from routine") {
                        let upNext = ProgramLibrary.upNext(in: ProgramLibrary.days(of: activeProgram, in: routines), context: context)
                        ForEach(startable) { routine in
                            let style = RoutineStyle(name: routine.name)
                            let isNext = routine.id == upNext?.id
                            Button {
                                start(routine)
                            } label: {
                                StartRow(
                                    title: routine.name,
                                    detail: "\(routine.liveItems.count) exercises · \(routine.liveItems.reduce(0) { $0 + $1.targetSets }) sets",
                                    exercises: routine.liveItems.compactMap { $0.exercise?.name }.joined(separator: " · "),
                                    symbol: style.symbol, colors: style.colors, isNext: isNext
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(isNext ? Color.orange.opacity(0.1) : nil)
                        }
                        if routines.isEmpty {
                            Text("Pick a ready-made program in Routines → Programs, or create your own routine there.").foregroundStyle(.secondary)
                        }
                    }
                    WorkoutHistorySections()
                }
                .navigationTitle("Workout")
            }
        }
    }

    private func start(_ routine: Routine?) {
        _ = Workout.start(routine: routine, unit: WeightUnit(rawValue: unitRaw) ?? .lb, context: context)
        try? context.save()
    }
}

/// A colored icon tile per kind of day, picked from the routine's name.
struct RoutineStyle {
    let symbol: String
    let colors: [Color]

    init(name: String) {
        let n = name.lowercased()
        switch true {
        case n.contains("push"): (symbol, colors) = ("arrow.up.right", [.orange, .red])
        case n.contains("pull"): (symbol, colors) = ("arrow.down.left", [.teal, .cyan])
        case n.contains("leg"): (symbol, colors) = ("figure.strengthtraining.functional", [.green, .mint])
        case n.contains("upper"): (symbol, colors) = ("figure.arms.open", [.purple, .pink])
        case n.contains("lower"): (symbol, colors) = ("figure.step.training", [.indigo, .purple])
        case n.contains("delt"), n.contains("arm"), n.contains("shoulder"): (symbol, colors) = ("dumbbell.fill", [.pink, .orange])
        case n.contains("chest"), n.contains("back"): (symbol, colors) = ("figure.strengthtraining.traditional", [.red, .orange])
        default: (symbol, colors) = ("bolt.fill", [.yellow, .orange])
        }
    }
}

/// Start button row: gradient icon tile, title, details and an optional "Up next" badge.
struct StartRow: View {
    let title: String
    let detail: String
    var exercises: String?
    let symbol: String
    let colors: [Color]
    var isNext = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    if isNext {
                        Text("UP NEXT")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let exercises, !exercises.isEmpty {
                    Text(exercises).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
