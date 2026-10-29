import LiftKit
import SwiftData
import SwiftUI

struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Routine> { $0.deletedAt == nil }, sort: \Routine.position) private var routines: [Routine]
    @AppStorage(Prefs.activeProgram) private var activeProgram: String?

    private var programDays: [Routine] { ProgramLibrary.days(of: activeProgram, in: routines) }
    private var ownRoutines: [Routine] { routines.filter { $0.program == nil } }

    /// Programs switched to earlier; their days stay here but not on the Workout tab.
    private var otherPrograms: [String] {
        Array(Set(routines.compactMap(\.program)).subtracting([activeProgram].compactMap { $0 })).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                // A row rather than a toolbar item: iOS 26 folds extra toolbar items into the ⋯ menu.
                Section {
                    NavigationLink { ProgramsView() } label: { Label("Programs", systemImage: "calendar") }
                }
                if let program = activeProgram, !programDays.isEmpty {
                    let upNext = ProgramLibrary.upNext(in: programDays, context: context)
                    Section(ProgramLibrary.name(for: program, routines: programDays)) {
                        rows(programDays, upNext: upNext)
                    }
                }
                if !ownRoutines.isEmpty {
                    Section("My routines") {
                        rows(ownRoutines)
                            .onMove { from, to in
                                var ordered = ownRoutines
                                ordered.move(fromOffsets: from, toOffset: to)
                                for (index, routine) in ordered.enumerated() where routine.position != index {
                                    routine.position = index
                                    routine.touch()
                                }
                            }
                    }
                }
                ForEach(otherPrograms, id: \.self) { program in
                    let days = ProgramLibrary.days(of: program, in: routines)
                    Section("\(ProgramLibrary.name(for: program, routines: days)) (not active)") {
                        rows(days)
                    }
                }
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView("No routines", systemImage: "list.bullet.rectangle", description: Text("Save your usual workouts as routines."))
                }
            }
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button("New", systemImage: "plus") {
                        context.insert(Routine(name: "New Routine", position: (routines.map(\.position).max() ?? -1) + 1))
                        try? context.save()
                    }
                }
            }
        }
    }

    private func rows(_ list: [Routine], upNext: Routine? = nil) -> some DynamicViewContent {
        ForEach(list) { routine in
            NavigationLink {
                RoutineEditor(routine: routine)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(routine.name).font(.headline)
                        Text(routine.isRestDay ? "Rest or light cardio" : "\(routine.liveItems.count) exercises").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if routine.id == upNext?.id { Text("Up next").font(.caption.bold()).foregroundStyle(.tint) }
                }
            }
        }
        .onDelete { offsets in
            for index in offsets { list[index].softDelete() }
        }
    }
}

struct RoutineEditor: View {
    @Bindable var routine: Routine
    @Environment(\.modelContext) private var context
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @Query(filter: Workout.inProgress) private var active: [Workout]
    @State private var showingPicker = false

    var body: some View {
        List {
            Section {
                TextField("Name", text: $routine.name.onSet(routine.touch)).font(.title3.bold())
                TextField("Notes", text: Binding(
                    get: { routine.notes ?? "" },
                    set: { routine.notes = $0.isEmpty ? nil : $0; routine.touch() }
                ), axis: .vertical)
            }
            Section("Exercises") {
                ForEach(routine.liveItems) { item in
                    RoutineItemRow(item: item)
                }
                .onDelete { offsets in
                    let items = routine.liveItems
                    for index in offsets { items[index].softDelete() }
                }
                .onMove { from, to in
                    var items = routine.liveItems
                    items.move(fromOffsets: from, toOffset: to)
                    for (index, item) in items.enumerated() where item.position != index {
                        item.position = index
                        item.touch()
                    }
                }
                Button("Add exercise", systemImage: "plus") { showingPicker = true }
            }
            Section {
                Button("Start workout", systemImage: "play.fill") {
                    _ = Workout.start(routine: routine, unit: WeightUnit(rawValue: unitRaw) ?? .lb, context: context)
                    try? context.save()
                }
                .disabled(!active.isEmpty)
            } footer: {
                if !active.isEmpty { Text("Finish your current workout first.") }
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingPicker) {
            ExercisePicker { exercise in
                let item = RoutineExercise(position: (routine.items.map(\.position).max() ?? -1) + 1)
                context.insert(item)
                item.routine = routine
                item.exercise = exercise
                item.restSeconds = exercise.defaultRestSeconds
                routine.touch()
            }
        }
    }
}

struct RoutineItemRow: View {
    @Bindable var item: RoutineExercise
    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil }) private var exercises: [Exercise]
    @AppStorage(Prefs.campus) private var campus = ""

    private var attachment: Binding<String> {
        Binding(
            get: { item.attachment ?? "" },
            set: { item.attachment = $0.isEmpty ? nil : String($0.prefix(80)); item.touch() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.exercise?.name ?? "Exercise").font(.headline)
                Spacer()
                if let current = item.exercise {
                    let options = GymLibrary.substitutes(for: current.id, among: exercises)
                    if !options.isEmpty {
                        Menu {
                            ForEach(options) { option in
                                Button(option.name) {
                                    item.exercise = option
                                    item.touch()
                                }
                            }
                        } label: {
                            Label("Swap", systemImage: "arrow.triangle.2.circlepath").labelStyle(.iconOnly)
                        }
                        .accessibilityLabel(campus == "gatech" ? "Swap for a CRC alternative" : "Swap for the same movement")
                    }
                }
            }
            Stepper("\(item.targetSets) sets", value: $item.targetSets.onSet(item.touch), in: 1...20)
            HStack {
                Text("Reps")
                TextField("min", value: $item.repMin.onSet(item.touch), format: .number)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 56)
                Text("–")
                TextField("max", value: $item.repMax.onSet(item.touch), format: .number)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 56)
                Spacer()
                Text("Rest")
                TextField("sec", value: $item.restSeconds.onSet(item.touch), format: .number)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 64)
            }
            .font(.subheadline)
            if item.exercise?.equipment == "cable" || item.attachment != nil {
                TextField("Attachment, e.g. Rope · top pulley", text: attachment)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
