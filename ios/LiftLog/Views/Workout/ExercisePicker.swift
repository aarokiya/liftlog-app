import SwiftData
import SwiftUI

struct ExercisePicker: View {
    var onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil }, sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var creating = false

    private var groups: [(muscle: String, exercises: [Exercise])] {
        let matches = search.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return Dictionary(grouping: matches, by: \.primaryMuscle)
            .map { (muscle: $0.key, exercises: $0.value) }
            .sorted { Muscle.label($0.muscle) < Muscle.label($1.muscle) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.muscle) { group in
                    Section(Muscle.label(group.muscle)) {
                        ForEach(group.exercises) { exercise in
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(exercise.name).foregroundStyle(.primary)
                                    if let equipment = exercise.equipment {
                                        Text(Format.equipment(equipment)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("New", systemImage: "plus") { creating = true } }
            }
            .sheet(isPresented: $creating) {
                NewExerciseView(initialName: search) { exercise in
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }
}

struct NewExerciseView: View {
    var initialName: String
    var onCreate: (Exercise) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var equipment = "barbell"
    @State private var primary = "chest"
    @State private var secondary: Set<String> = []
    @State private var rest = 120

    private let equipmentOptions = ["barbell", "dumbbell", "machine", "cable", "bodyweight", "kettlebell", "band", "other"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Equipment", selection: $equipment) {
                    ForEach(equipmentOptions, id: \.self) { Text(Format.equipment($0)) }
                }
                Picker("Primary muscle", selection: $primary) {
                    ForEach(Muscle.all, id: \.id) { Text($0.label).tag($0.id) }
                }
                Stepper("Rest \(Format.clock(TimeInterval(rest)))", value: $rest, in: 15...600, step: 15)
                Section("Secondary muscles") {
                    ForEach(Muscle.all.filter { $0.id != primary }, id: \.id) { muscle in
                        Toggle(muscle.label, isOn: Binding(
                            get: { secondary.contains(muscle.id) },
                            set: { if $0 { secondary.insert(muscle.id) } else { secondary.remove(muscle.id) } }
                        ))
                    }
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = initialName }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let exercise = Exercise(
                            name: name.trimmingCharacters(in: .whitespaces), equipment: equipment,
                            primaryMuscle: primary, secondaryMuscles: secondary.sorted(), defaultRestSeconds: rest
                        )
                        context.insert(exercise)
                        try? context.save()
                        onCreate(exercise)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
