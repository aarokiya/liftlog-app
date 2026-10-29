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
            // Name and a quiet summary line as a header, without a card; the live clock sits in the navigation bar.
            Section {
                if !isActive {
                    DatePicker("Started", selection: $workout.startedAt.onSet(workout.touch))
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $workout.name.onSet(workout.touch))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(summary).font(.caption.monospacedDigit()).foregroundStyle(Color.secondary)
                }
                .textCase(nil)
            }

            let plan = planItems
            ForEach(workout.liveExercises) { we in
                ExerciseSection(workoutExercise: we, plan: plan.first { $0.exercise?.id == we.exercise?.id }, isActive: isActive, unit: unit)
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
        .environment(\.defaultMinListRowHeight, 14)
        .listSectionSpacing(6)
        .navigationTitle(isActive ? "" : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if isActive {
                ToolbarItem(placement: .principal) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Format.clock(context.date.timeIntervalSince(workout.startedAt)))
                            .font(.headline.monospacedDigit())
                            .accessibilityLabel("Elapsed time")
                    }
                }
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

    /// "4 of 18 sets · 5,240 lb" while training; "1:05 · 18 sets · 5,240 lb" afterwards.
    private var summary: String {
        let sets = workout.liveExercises.flatMap(\.liveSets)
        let done = sets.filter { $0.completedAt != nil }.count
        let volume = Volume.load(workout.liftSets(), unit: unit)
        let count = "\(sets.count) set\(sets.count == 1 ? "" : "s")"
        return [
            isActive ? nil : workout.duration.map(Format.duration),
            isActive ? "\(done) of \(count)" : count,
            volume > 0 ? Format.volume(volume, unit) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// The routine this workout was started from, for each exercise's attachment, target and notes.
    private var planItems: [RoutineExercise] {
        guard let id = workout.routineId else { return [] }
        return (try? context.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id })).first?.liveItems) ?? []
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
    /// This exercise in the routine the workout came from: attachment and notes.
    var plan: RoutineExercise?
    var isActive: Bool
    var unit: WeightUnit
    @Environment(\.modelContext) private var context
    @Environment(RestTimer.self) private var restTimer
    @State private var showingNotes = false

    /// Starts the rest timer after a set is ticked; there's none after cardio.
    private var startRest: () -> Void {
        let timer = restTimer
        let isCardio = workoutExercise.exercise?.isCardio ?? false
        let seconds = plan?.restSeconds ?? workoutExercise.exercise?.defaultRestSeconds ?? 120
        return { if !isCardio { timer.start(seconds: seconds) } }
    }

    var body: some View {
        let sets = workoutExercise.liveSets
        let previous = workoutExercise.previousSets
        let timed = workoutExercise.exercise?.isTimed ?? false
        let rest = startRest
        // The name is the section's first row rather than a header, which keeps the space between exercises small.
        Section {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 16) {
                    Text(workoutExercise.exercise?.name ?? "Exercise").font(.footnote.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if plan?.notes != nil {
                        Button { showingNotes.toggle() } label: {
                            Image(systemName: showingNotes ? "info.circle.fill" : "info.circle")
                        }
                        .accessibilityLabel(showingNotes ? "Hide notes" : "Show notes")
                    }
                    Button { workoutExercise.addSet(unit: unit, context: context) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add set")
                    Menu {
                        Button("Remove exercise", systemImage: "trash", role: .destructive) {
                            workoutExercise.softDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                // What to clip on, and this workout's own notes, e.g. a rest-day preset's machine settings.
                ForEach([plan?.attachment, workoutExercise.notes].compactMap { $0 }, id: \.self) { line in
                    Text(line).font(.caption2).foregroundStyle(.secondary)
                }
                if showingNotes, let notes = plan?.notes {
                    Text(notes).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }
                if let note = workoutExercise.exercise?.stickyNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetRowView(set: set, hint: workoutExercise.placeholder(at: index, in: sets, previous: previous),
                           isTimed: timed, isActive: isActive, onComplete: rest)
                    .listRowInsets(SetRowView.insets)
                    .listRowSeparator(.hidden)
            }
            .onDelete { offsets in
                for index in offsets { sets[index].softDelete() }
            }
        }
    }
}

/// One set as a line you type into: "[25] lb × [12]" (or "[25] min"), with the checkbox during the workout. Empty
/// fields show last time's numbers greyed, and ticking the box logs those. Warm-up, drop and failure sets get a coloured
/// letter in the margin; long-press to change the type or delete the set.
struct SetRowView: View {
    /// The margin left of the line for the set type's letter; the line stays at the usual row inset.
    static let gutter: CGFloat = 12
    static let insets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)
    @Bindable var set: WorkoutSet
    /// Last time's numbers, shown greyed out until the set is entered.
    let hint: SetHint
    /// Minutes instead of weight × reps.
    var isTimed = false
    let isActive: Bool
    var onComplete: () -> Void

    private enum Field { case weight, reps, minutes }
    @FocusState private var focus: Field?

    var body: some View {
        HStack(spacing: 0) {
            Text(set.setType.marker)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(set.setType.color)
                .frame(width: Self.gutter)
                .accessibilityHidden(true)
            if isTimed {
                zone(.minutes, minWidth: 72) {
                    number(hint.seconds.map { Format.number(Double($0) / 60) }, value: minutes, label: "Minutes").focused($focus, equals: .minutes)
                    Text(" min").foregroundStyle(.secondary)
                }
            } else {
                zone(.weight, minWidth: 76) {
                    number(hint.weight.map(Format.number), value: $set.weight.onSet(set.touch), label: "Weight").focused($focus, equals: .weight)
                    Text(" \(set.unit.rawValue) ×").foregroundStyle(.secondary)
                }
                zone(.reps, minWidth: 52) {
                    TextField(hint.reps.map(String.init) ?? "0", value: $set.reps.onSet(set.touch), format: .number)
                        .keyboardType(.numberPad)
                        .fixedSize()
                        .focused($focus, equals: .reps)
                        .accessibilityLabel("Reps")
                }
            }
            Spacer(minLength: 0)
            if focus != nil {
                // Closes the number pad, which has no return key.
                Button("Done") { focus = nil }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            } else if isActive {
                Button(action: toggle) {
                    Image(systemName: set.completedAt == nil ? "circle" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(set.completedAt == nil ? Color.secondary : Color.green)
                }
                .buttonStyle(.borderless)
                .sensoryFeedback(.success, trigger: set.completedAt)
                .accessibilityLabel("Done")
                .accessibilityAddTraits(set.completedAt != nil ? .isSelected : [])
            }
        }
        .font(.footnote.monospacedDigit())
        .contextMenu {
            Picker("Set type", selection: $set.setType.onSet(set.touch)) {
                ForEach(SetType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Delete set", systemImage: "trash", role: .destructive) { set.softDelete() }
        }
    }

    /// A tap target around a small field: the text stays small, but a tap anywhere in the row's height and `minWidth`
    /// starts typing in it.
    private func zone(_ field: Field, minWidth: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 0) { content() }
            .frame(minWidth: minWidth, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focus = field }
    }

    /// A decimal field as wide as its number, so the line reads like text; the placeholder is last time's value.
    private func number(_ placeholder: String?, value: Binding<Double?>, label: String) -> some View {
        TextField(placeholder ?? "0", value: value, format: .number)
            .keyboardType(.decimalPad)
            .fixedSize()
            .accessibilityLabel(label)
    }

    /// Typed as minutes (decimals allowed), stored as whole seconds.
    private var minutes: Binding<Double?> {
        Binding(
            get: { set.durationSeconds.map { Double($0) / 60 } },
            set: { set.durationSeconds = $0.map { Int(($0 * 60).rounded()) }; set.touch() }
        )
    }

    private func toggle() {
        if set.completedAt == nil {
            if isTimed {
                // Nothing to record yet: no minutes typed and none from last time.
                guard ((set.durationSeconds ?? hint.seconds) ?? 0) > 0 else { return }
                if set.durationSeconds == nil { set.durationSeconds = hint.seconds }
            } else {
                // Nothing to record yet: no reps typed and none from last time.
                guard ((set.reps ?? hint.reps) ?? 0) > 0 else { return }
                if set.weight == nil { set.weight = hint.weight }
                if set.reps == nil { set.reps = hint.reps }
            }
            set.completedAt = .now
            onComplete()
        } else {
            set.completedAt = nil
        }
        set.touch()
    }
}

extension SetType {
    var title: String {
        switch self {
        case .warmup: "Warm-up"
        case .working: "Working"
        case .drop: "Drop set"
        case .failure: "To failure"
        }
    }

    /// The letter in the set's margin; working sets have none.
    var marker: String {
        switch self {
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        case .working: ""
        }
    }

    var color: Color {
        switch self {
        case .warmup: .orange
        case .drop: .purple
        case .failure: .red
        case .working: .primary
        }
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
