import Foundation
import LiftKit
import SwiftData

/// A light cardio set-up for a rest day on the stair climber or treadmill: how long, and what to set on the machine.
struct CardioPreset: Identifiable {
    let id: String
    let name: String
    /// The built-in Stairmaster or Incline Walk (Treadmill).
    let exerciseId: UUID
    let minutes: Int
    /// What to set on the machine, e.g. "3.0 mph · 12% incline".
    let settings: String
    /// How it should feel.
    let detail: String

    /// Saved as the exercise's notes, so the settings show under it during the workout.
    var note: String { "\(name) · \(settings)" }
}

/// Rest-day cardio stays in zone 2 (about 60–70% of max heart rate, still able to talk in full sentences): it adds
/// aerobic work and blood flow without taking recovery from lifting. Levels are StairMaster's 1–20; inclines in %.
enum CardioPresets {
    static let stairmaster = UUID(uuidString: "00000000-0000-4000-8000-000000000070")!
    static let treadmill = UUID(uuidString: "00000000-0000-4000-8000-000000000071")!
    static let machines = [stairmaster, treadmill]

    static let all: [CardioPreset] = [
        CardioPreset(id: "stairs-easy", name: "Easy steady", exerciseId: stairmaster, minutes: 20,
                     settings: "Level 4–6", detail: "Upright, whole foot on each step, breathing through your nose if you can."),
        CardioPreset(id: "stairs-ramp", name: "Gentle ramp", exerciseId: stairmaster, minutes: 25,
                     settings: "Level 3, +1 every 5 min, max 6", detail: "Eases in. Stop climbing levels once talking gets hard."),
        CardioPreset(id: "stairs-long", name: "Long easy", exerciseId: stairmaster, minutes: 30,
                     settings: "Level 4–5", detail: "More aerobic base for little fatigue. Slow down if your legs start to burn."),
        CardioPreset(id: "walk-recovery", name: "Recovery walk", exerciseId: treadmill, minutes: 20,
                     settings: "3.0 mph · 5% incline", detail: "The lightest option, e.g. the day after legs."),
        CardioPreset(id: "walk-zone2", name: "Zone 2 incline walk", exerciseId: treadmill, minutes: 40,
                     settings: "3.0–3.4 mph · 8–10% incline", detail: "The steepest incline where you can still talk. 30–45 min."),
        CardioPreset(id: "walk-12-3-30", name: "12-3-30", exerciseId: treadmill, minutes: 30,
                     settings: "3.0 mph · 12% incline", detail: "Harder than it looks: drop to 10% if you can't talk in full sentences."),
    ]

    static func presets(for exerciseId: UUID?) -> [CardioPreset] {
        all.filter { $0.exerciseId == exerciseId }
    }
}

extension Workout {
    /// Starts a rest day's cardio from a preset: one set with the preset's minutes typed in (still to tick), and its
    /// settings as the exercise's notes.
    static func start(_ preset: CardioPreset, on exercise: Exercise, routine: Routine?, unit: WeightUnit, context: ModelContext) -> Workout {
        let workout = Workout(name: routine?.name ?? "Light cardio", routineId: routine?.id)
        context.insert(workout)
        let we = workout.add(exercise, unit: unit, context: context)
        we.notes = preset.note
        we.touch()
        if let set = we.liveSets.first {
            set.durationSeconds = preset.minutes * 60
            set.touch()
        }
        return workout
    }
}
