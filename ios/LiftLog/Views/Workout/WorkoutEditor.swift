import LiftKit
import SwiftData
import SwiftUI

/// Edits a workout. `isActive` is the live in-gym view; otherwise it's editing a past workout.
struct WorkoutEditor: View {
    @Bindable var workout: Workout
    var isActive: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(HealthService.self) private var health
    @Environment(SyncService.self) private var sync
    @Environment(RestTimer.self) private var restTimer
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @State private var showingPicker = false
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .lb }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $workout.name.onSet(workout.touch)).font(.title3.bold())
                if isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LabeledContent("Elapsed", value: Format.clock(context.date.timeIntervalSince(workout.startedAt)))
                            .monospacedDigit()
                    }
                } else {
                    DatePicker("Started", selection: $workout.startedAt.onSet(workout.touch))
                    if let duration = workout.duration {
                        LabeledContent("Duration", value: Format.duration(duration))
                    }
                }
                LabeledContent("Volume", value: Format.volume(Volume.load(workout.liftSets(), unit: unit), unit))
            }

            ForEach(workout.liveExercises) { we in
                ExerciseSection(workoutExercise: we, isActive: isActive, unit: unit)
            }

            Section {
                Button("Add exercise", systemImage: "plus") { showingPicker = true }
            }

            Section("Notes") {
                TextField("How did it go?", text: notesBinding, axis: .vertical)
            }

            if !isActive {
                Section {
                    Button("Delete workout", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(isActive ? "Workout" : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if isActive {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard", role: .destructive) { confirmingDiscard = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { finish() }.bold()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isActive { RestTimerBar() }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePicker { exercise in
                workout.add(exercise, unit: unit, context: context)
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmingDiscard) {
            Button("Discard workout", role: .destructive) {
                restTimer.stop()
                workout.softDelete()
                try? context.save()
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                workout.softDelete()
                try? context.save()
                dismiss()
            }
        }
        .onDisappear { try? context.save() }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { workout.notes ?? "" },
            set: { workout.notes = $0.isEmpty ? nil : $0; workout.touch() }
        )
    }

    private func finish() {
        restTimer.stop()
        workout.finish()
        try? context.save()
        Task {
            await health.sync(context: context)
            await sync.run(context: context, auth: auth)
        }
    }
}

struct ExerciseSection: View {
    @Bindable var workoutExercise: WorkoutExercise
    var isActive: Bool
    var unit: WeightUnit
    @Environment(\.modelContext) private var context
    @Environment(RestTimer.self) private var restTimer

    var body: some View {
        let sets = workoutExercise.liveSets
        let previous = workoutExercise.previousSets
        Section {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetRowView(set: set, number: workingNumber(sets, index), hint: workoutExercise.placeholder(at: index, in: sets, previous: previous), isActive: isActive) {
                    restTimer.start(seconds: workoutExercise.exercise?.defaultRestSeconds ?? 120)
                }
                .listRowBackground(set.completedAt != nil ? Color.green.opacity(0.18) : nil)
            }
            .onDelete { offsets in
                for index in offsets { sets[index].softDelete() }
            }
            Button("Add set", systemImage: "plus") {
                workoutExercise.addSet(unit: unit, context: context)
            }
            .font(.subheadline)
        } header: {
            HStack {
                Text(workoutExercise.exercise?.name ?? "Exercise").font(.headline).textCase(nil)
                Spacer()
                Menu {
                    Button("Remove exercise", systemImage: "trash", role: .destructive) {
                        workoutExercise.softDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        } footer: {
            if let note = workoutExercise.exercise?.stickyNote { Text(note) }
        }
    }

    /// Warmups don't consume a set number, matching how lifters count working sets.
    private func workingNumber(_ sets: [WorkoutSet], _ index: Int) -> Int {
        sets[...index].filter { $0.setType != .warmup }.count
    }
}

struct SetRowView: View {
    @Bindable var set: WorkoutSet
    let number: Int
    /// Last time's numbers, shown greyed out until you type.
    let hint: (weight: Double?, reps: Int?)
    let isActive: Bool
    var onComplete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Set type", selection: $set.setType.onSet(set.touch)) {
                    ForEach(SetType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            } label: {
                Text(label)
                    .font(.subheadline.bold())
                    .frame(width: 28)
                    .foregroundStyle(color)
            }

            TextField(hint.weight.map(Format.number) ?? "weight", value: $set.weight.onSet(set.touch), format: .number)
                .accessibilityLabel("Weight")
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 84)
                .textFieldStyle(.roundedBorder)
            Text(set.unit.rawValue).font(.caption).foregroundStyle(.secondary)

            TextField(hint.reps.map(String.init) ?? "reps", value: $set.reps.onSet(set.touch), format: .number)
                .accessibilityLabel("Reps")
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)

            Spacer(minLength: 0)

            if isActive {
                Button(action: toggle) {
                    Image(systemName: set.completedAt == nil ? "circle" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(set.completedAt == nil ? Color.secondary : Color.green)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: set.completedAt)
            }
        }
    }

    private var label: String {
        switch set.setType {
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        case .working: "\(number)"
        }
    }

    private var color: Color {
        switch set.setType {
        case .warmup: .orange
        case .drop: .purple
        case .failure: .red
        case .working: .primary
        }
    }

    private func toggle() {
        if set.completedAt == nil {
            // Nothing to record yet: no reps typed and none from last time.
            guard ((set.reps ?? hint.reps) ?? 0) > 0 else { return }
            if set.weight == nil { set.weight = hint.weight }
            if set.reps == nil { set.reps = hint.reps }
            set.completedAt = .now
            onComplete()
        } else {
            set.completedAt = nil
        }
        set.touch()
    }
}

struct RestTimerBar: View {
    @Environment(RestTimer.self) private var timer

    var body: some View {
        if let endsAt = timer.endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, endsAt.timeIntervalSince(context.date))
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                    Text(Format.clock(remaining)).monospacedDigit().bold()
                    ProgressView(value: timer.duration > 0 ? remaining / timer.duration : 0)
                    Button("-15") { timer.add(-15) }
                    Button("+15") { timer.add(15) }
                    Button { timer.stop() } label: { Image(systemName: "xmark.circle.fill") }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.thinMaterial)
            }
        }
    }
}
