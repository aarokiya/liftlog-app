import LiftKit
import SwiftData
import SwiftUI

/// Starting a rest day: optional light cardio, as set-ups for the stair climber and treadmill, or just rest.
struct RestDaySheet: View {
    let routine: Routine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .lb }

    /// Both machines with presets, the routine's own first.
    private var machines: [Exercise] {
        let ids = CardioPresets.machines
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let order = routine.liveItems.compactMap(\.exercise?.id).filter(ids.contains) + ids
        return exercises.sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
    }

    /// The routine's other cardio (e.g. a bike), offered as it is.
    private var others: [RoutineExercise] {
        routine.liveItems.filter { $0.exercise != nil && CardioPresets.presets(for: $0.exercise?.id).isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Text("Keep it zone 2, easy enough to talk in full sentences (60–70% of max heart rate), so it doesn't eat into recovery.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)

                ForEach(machines) { exercise in
                    Section {
                        ForEach(CardioPresets.presets(for: exercise.id)) { preset in
                            Button {
                                _ = Workout.start(preset, on: exercise, routine: routine, unit: unit, context: context)
                                started()
                            } label: {
                                PresetRow(preset: preset)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(exercise.name)
                    } footer: {
                        Text(exercise.id == CardioPresets.stairmaster
                             ? "Stand tall with your hands off the rails; leaning on them makes any level easier than it says."
                             : "Let your arms swing: holding the rails takes away a big part of the work.")
                    }
                }

                if !others.isEmpty {
                    Section("Other cardio") {
                        ForEach(others) { item in
                            Button(item.exercise?.name ?? "Cardio") {
                                _ = Workout.start(routine: routine, items: [item], unit: unit, context: context)
                                started()
                            }
                        }
                    }
                }
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Just rest") { dismiss() }
                }
            }
        }
    }

    private func started() {
        try? context.save()
        dismiss()
    }
}

private struct PresetRow: View {
    let preset: CardioPreset

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.headline)
                Text(preset.settings).font(.subheadline)
                Text(preset.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("\(preset.minutes) min").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
