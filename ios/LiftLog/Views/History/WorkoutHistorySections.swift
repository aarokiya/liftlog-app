import LiftKit
import SwiftData
import SwiftUI

/// Past workouts by month, shown under the start buttons on the Workout tab.
struct WorkoutHistorySections: View {
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @Query(filter: Workout.finished, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .lb }

    private var months: [(month: Date, workouts: [Workout])] {
        let calendar = Calendar.current
        return Dictionary(grouping: workouts) { calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
            .map { (month: $0.key, workouts: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        ForEach(months, id: \.month) { group in
            Section(group.month.formatted(.dateTime.month(.wide).year())) {
                ForEach(group.workouts) { workout in
                    NavigationLink {
                        WorkoutEditor(workout: workout, isActive: false)
                    } label: {
                        WorkoutSummaryRow(workout: workout, unit: unit)
                    }
                }
            }
        }
    }
}

struct WorkoutSummaryRow: View {
    let workout: Workout
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.name).font(.headline)
                Spacer()
                Text(workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day())).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let duration = workout.duration { Label(Format.duration(duration), systemImage: "clock") }
                let volume = Volume.load(workout.liftSets(), unit: unit)
                if volume > 0 { Label(Format.volume(volume, unit), systemImage: "scalemass") }
                Label("\(workout.liveExercises.count)", systemImage: "list.bullet")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(workout.liveExercises.map(Self.summary).joined(separator: "\n"))
                .font(.caption)
                .lineLimit(4)
        }
    }

    /// "3× Hack Squat", or "25 min Stairmaster" for timed exercises.
    static func summary(_ we: WorkoutExercise) -> String {
        let name = we.exercise?.name ?? ""
        guard we.exercise?.isTimed == true else { return "\(we.liveSets.count)× \(name)" }
        let seconds = we.liveSets.compactMap(\.durationSeconds).reduce(0, +)
        return "\(Format.number(Double(seconds) / 60)) min \(name)"
    }
}
