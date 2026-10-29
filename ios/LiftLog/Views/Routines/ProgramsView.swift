import LiftKit
import SwiftData
import SwiftUI

/// Program template shared with the web (shared/programs/*.json, bundled as resources).
struct ProgramTemplate: Decodable, Identifiable {
    struct Item: Decodable {
        let exercise: ExerciseRef
        let sets: Int
        /// [min, max]; cardio (minutes) has none.
        let reps: [Int]?
        let rest: Int?
        let notes: String?
        /// What to clip on, e.g. "Rope · top pulley".
        let attachment: String?
    }

    struct Day: Decodable {
        let name: String
        let exercises: [Item]
    }

    /// Built-in exercise number or a full exercise uuid.
    enum ExerciseRef: Decodable {
        case builtIn(Int)
        case id(UUID)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let n = try? container.decode(Int.self) {
                self = .builtIn(n)
            } else {
                self = .id(try container.decode(UUID.self))
            }
        }

        var uuid: UUID? {
            switch self {
            case let .builtIn(n): UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))
            case let .id(id): id
            }
        }
    }

    let id: String
    let name: String
    let split: String
    let schedule: String?
    let days: [Day]
}

enum ProgramLibrary {
    static let templates: [ProgramTemplate] = ["ppl", "ul", "pplul", "arnold", "lkc"].compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProgramTemplate.self, from: data)
    }

    static func name(for id: String, routines: [Routine]) -> String {
        templates.first { $0.id == id }?.name
            ?? id.replacingOccurrences(of: "custom-", with: "").split(separator: "-").map(\.capitalized).joined(separator: " ")
    }

    /// A program's days in schedule order.
    static func days(of program: String?, in routines: [Routine]) -> [Routine] {
        guard let program else { return [] }
        return routines.filter { $0.program == program }.sorted { ($0.programDay ?? 0) < ($1.programDay ?? 0) }
    }

    /// A 7-day program follows the calendar: today's weekday's routine (day 0 is Monday), rest day included. Otherwise
    /// it's the day after the most recent workout started from one of `days`, and each calendar day that has gone by
    /// since then uses up a rest day, so resting without logging cardio doesn't hold up the rotation.
    @MainActor
    static func upNext(in days: [Routine], context: ModelContext) -> Routine? {
        if days.count == 7 { return days[WeekStrip.todayIndex] }
        let ids = days.map(\.id)
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.deletedAt == nil && $0.routineId != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let last = (try? context.fetch(descriptor))?.first { ids.contains($0.routineId!) }
        guard let last, let index = ids.firstIndex(of: last.routineId!) else { return days.first }
        var next = (index + 1) % days.count
        var daysOff = LocalDate(date: .now).dayNumber - LocalDate(date: last.startedAt).dayNumber - 1
        var skipped = 0
        while daysOff > 0, days[next].isRestDay, skipped < days.count {
            next = (next + 1) % days.count
            daysOff -= 1
            skipped += 1
        }
        return days[next]
    }

    @MainActor
    static func install(_ template: ProgramTemplate, context: ModelContext, after position: Int) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (day, d) in template.days.enumerated() {
            let routine = Routine(name: d.name, position: position + day)
            routine.program = template.id
            routine.programDay = day
            routine.notes = day == 0 ? template.schedule : nil
            context.insert(routine)
            for (index, item) in d.exercises.enumerated() {
                guard let id = item.exercise.uuid, let exercise = byId[id] else { continue }
                let entry = RoutineExercise(position: index, targetSets: item.sets, repMin: item.reps?.first, repMax: item.reps?.last)
                context.insert(entry)
                entry.routine = routine
                entry.exercise = exercise
                entry.restSeconds = item.rest ?? exercise.defaultRestSeconds
                entry.notes = item.notes
                entry.attachment = item.attachment
            }
        }
        try? context.save()
    }
}

struct ProgramsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Routine> { $0.deletedAt == nil }, sort: \Routine.position) private var routines: [Routine]
    @AppStorage(Prefs.activeProgram) private var activeProgram: String?
    @AppStorage(Prefs.campus) private var campus = ""
    @AppStorage(Prefs.profileNeedsSync) private var profileNeedsSync = false

    private var customPrograms: [String] {
        let templateIds = Set(ProgramLibrary.templates.map(\.id))
        return Array(Set(routines.compactMap(\.program))).filter { !templateIds.contains($0) }.sorted()
    }

    var body: some View {
        List {
            Section {
                ForEach(ProgramLibrary.templates) { template in
                    row(id: template.id, title: template.name, subtitle: template.days.map(\.name).joined(separator: " · ")) {
                        if !routines.contains(where: { $0.program == template.id }) {
                            ProgramLibrary.install(template, context: context, after: (routines.map(\.position).max() ?? -1) + 1)
                        }
                    }
                }
            } footer: {
                Text(campus == "gatech"
                     ? "Built for Georgia Tech CRC equipment. Switching adds the program's days as routines the first time."
                     : "Uses machines, cables and free weights. If your gym lacks one, open the routine and tap the swap button for the same movement. Switching adds the program's days as routines the first time.")
            }
            if !customPrograms.isEmpty {
                Section("Imported") {
                    ForEach(customPrograms, id: \.self) { id in
                        row(id: id, title: ProgramLibrary.name(for: id, routines: routines), subtitle: routines.filter { $0.program == id }.map(\.name).joined(separator: " · ")) {}
                    }
                }
            }
            if activeProgram != nil {
                Button("Stop using a program", role: .destructive) { select(nil) }
            }
        }
        .navigationTitle("Programs")
    }

    private func row(id: String, title: String, subtitle: String, prepare: @escaping () -> Void) -> some View {
        Button {
            prepare()
            select(id)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if activeProgram == id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .foregroundStyle(.primary)
    }

    private func select(_ id: String?) {
        activeProgram = id
        profileNeedsSync = true
    }
}
