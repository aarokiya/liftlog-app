// Generated from supabase/seed.sql. Keep ids in sync with the server seed.
import Foundation
import SwiftData

enum BuiltInExercises {
    struct Seed {
        let id: String
        let name: String
        let kind: String
        let equipment: String
        let primary: String
        let secondary: [String]
    }

    static let all: [Seed] = [
        Seed(id: "00000000-0000-4000-8000-000000000001", name: "Bench Press (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "chest", secondary: ["triceps", "front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000002", name: "Incline Bench Press (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "chest", secondary: ["front_delts", "triceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000003", name: "Squat (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "quads", secondary: ["glutes", "adductors"]),
        Seed(id: "00000000-0000-4000-8000-000000000004", name: "Deadlift (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "hamstrings", secondary: ["glutes", "back", "forearms"]),
        Seed(id: "00000000-0000-4000-8000-000000000005", name: "Romanian Deadlift (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "hamstrings", secondary: ["glutes"]),
        Seed(id: "00000000-0000-4000-8000-000000000006", name: "Overhead Press (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "front_delts", secondary: ["triceps", "side_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000007", name: "Pull-up", kind: "bodyweight", equipment: "bodyweight", primary: "back", secondary: ["biceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000008", name: "Lat Pulldown (Cable)", kind: "weight_reps", equipment: "cable", primary: "back", secondary: ["biceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000009", name: "Bent Over Row (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "back", secondary: ["biceps", "rear_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000010", name: "Seated Cable Row", kind: "weight_reps", equipment: "cable", primary: "back", secondary: ["biceps", "rear_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000011", name: "Leg Press", kind: "weight_reps", equipment: "machine", primary: "quads", secondary: ["glutes"]),
        Seed(id: "00000000-0000-4000-8000-000000000012", name: "Leg Extension (Machine)", kind: "weight_reps", equipment: "machine", primary: "quads", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000013", name: "Lying Leg Curl (Machine)", kind: "weight_reps", equipment: "machine", primary: "hamstrings", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000014", name: "Hip Thrust (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "glutes", secondary: ["hamstrings"]),
        Seed(id: "00000000-0000-4000-8000-000000000015", name: "Standing Calf Raise (Machine)", kind: "weight_reps", equipment: "machine", primary: "calves", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000016", name: "Lateral Raise (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "side_delts", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000017", name: "Face Pull (Cable)", kind: "weight_reps", equipment: "cable", primary: "rear_delts", secondary: ["back"]),
        Seed(id: "00000000-0000-4000-8000-000000000018", name: "Bicep Curl (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "biceps", secondary: ["forearms"]),
        Seed(id: "00000000-0000-4000-8000-000000000019", name: "Hammer Curl (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "biceps", secondary: ["forearms"]),
        Seed(id: "00000000-0000-4000-8000-000000000020", name: "Triceps Pushdown (Cable)", kind: "weight_reps", equipment: "cable", primary: "triceps", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000021", name: "Skull Crusher (EZ Bar)", kind: "weight_reps", equipment: "ez_bar", primary: "triceps", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000022", name: "Dip", kind: "bodyweight", equipment: "bodyweight", primary: "chest", secondary: ["triceps", "front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000023", name: "Chest Fly (Cable)", kind: "weight_reps", equipment: "cable", primary: "chest", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000024", name: "Plank", kind: "duration", equipment: "bodyweight", primary: "core", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000025", name: "Hanging Leg Raise", kind: "bodyweight", equipment: "bodyweight", primary: "core", secondary: ["hip_flexors"]),
        Seed(id: "00000000-0000-4000-8000-000000000026", name: "Bulgarian Split Squat (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "quads", secondary: ["glutes"]),
        Seed(id: "00000000-0000-4000-8000-000000000027", name: "Front Squat (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "quads", secondary: ["glutes", "core"]),
        Seed(id: "00000000-0000-4000-8000-000000000028", name: "Shrug (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "traps", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000029", name: "Hip Adduction (Machine)", kind: "weight_reps", equipment: "machine", primary: "adductors", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000030", name: "Hip Abduction (Machine)", kind: "weight_reps", equipment: "machine", primary: "abductors", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000031", name: "Pec Deck (Machine)", kind: "weight_reps", equipment: "machine", primary: "chest", secondary: ["front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000032", name: "Lateral Raise (Machine)", kind: "weight_reps", equipment: "machine", primary: "side_delts", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000033", name: "Rear Delt Fly (Machine)", kind: "weight_reps", equipment: "machine", primary: "rear_delts", secondary: ["traps"]),
        Seed(id: "00000000-0000-4000-8000-000000000034", name: "Shoulder Press (Machine)", kind: "weight_reps", equipment: "machine", primary: "front_delts", secondary: ["triceps", "side_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000035", name: "Chest Press (Machine)", kind: "weight_reps", equipment: "machine", primary: "chest", secondary: ["triceps", "front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000036", name: "Incline Chest Press (Hammer Strength)", kind: "weight_reps", equipment: "plate_machine", primary: "chest", secondary: ["front_delts", "triceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000037", name: "Iso-Lateral Row (Hammer Strength)", kind: "weight_reps", equipment: "plate_machine", primary: "back", secondary: ["biceps", "rear_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000038", name: "Iso-Lateral Pulldown (Hammer Strength)", kind: "weight_reps", equipment: "plate_machine", primary: "back", secondary: ["biceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000039", name: "Preacher Curl (EZ Bar)", kind: "weight_reps", equipment: "ez_bar", primary: "biceps", secondary: ["forearms"]),
        Seed(id: "00000000-0000-4000-8000-000000000040", name: "Overhead Triceps Extension (Cable)", kind: "weight_reps", equipment: "cable", primary: "triceps", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000041", name: "Seated Dip (Machine)", kind: "weight_reps", equipment: "machine", primary: "triceps", secondary: ["chest", "front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000042", name: "Close-Grip Bench Press (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "triceps", secondary: ["chest", "front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000043", name: "Stiff-Leg Deadlift (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "hamstrings", secondary: ["glutes", "back"]),
        Seed(id: "00000000-0000-4000-8000-000000000044", name: "Wrist Curl (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "forearms", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000045", name: "Crunch", kind: "bodyweight", equipment: "bodyweight", primary: "core", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000046", name: "Cable Crunch", kind: "weight_reps", equipment: "cable", primary: "core", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000047", name: "Ab Crunch (Machine)", kind: "weight_reps", equipment: "machine", primary: "core", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000048", name: "Back Extension", kind: "weighted_bodyweight", equipment: "bodyweight", primary: "back", secondary: ["glutes", "hamstrings"]),
        Seed(id: "00000000-0000-4000-8000-000000000049", name: "Seated Calf Raise (Machine)", kind: "weight_reps", equipment: "machine", primary: "calves", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000050", name: "Seated Leg Curl (Machine)", kind: "weight_reps", equipment: "machine", primary: "hamstrings", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000051", name: "Hack Squat (Hammer Strength)", kind: "weight_reps", equipment: "plate_machine", primary: "quads", secondary: ["glutes"]),
        Seed(id: "00000000-0000-4000-8000-000000000052", name: "Trap Bar Deadlift", kind: "weight_reps", equipment: "trap_bar", primary: "quads", secondary: ["glutes", "hamstrings", "back"]),
        Seed(id: "00000000-0000-4000-8000-000000000053", name: "Incline Bench Press (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "chest", secondary: ["front_delts", "triceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000054", name: "Lateral Raise (Cable)", kind: "weight_reps", equipment: "cable", primary: "side_delts", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000055", name: "Low-to-High Fly (Cable)", kind: "weight_reps", equipment: "cable", primary: "chest", secondary: ["front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000056", name: "Assisted Chin-up (Machine)", kind: "assisted_bodyweight", equipment: "assisted_machine", primary: "back", secondary: ["biceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000057", name: "Assisted Dip (Machine)", kind: "assisted_bodyweight", equipment: "assisted_machine", primary: "chest", secondary: ["triceps", "front_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000058", name: "Walking Lunge (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "quads", secondary: ["glutes"]),
        Seed(id: "00000000-0000-4000-8000-000000000059", name: "Shoulder Press (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "front_delts", secondary: ["triceps", "side_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000060", name: "Straight-Arm Pulldown (Cable)", kind: "weight_reps", equipment: "cable", primary: "back", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000061", name: "Single-Arm Row (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "back", secondary: ["biceps", "rear_delts"]),
        Seed(id: "00000000-0000-4000-8000-000000000062", name: "Rear Delt Fly (Cable)", kind: "weight_reps", equipment: "cable", primary: "rear_delts", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000063", name: "Incline Curl (Dumbbell)", kind: "weight_reps", equipment: "dumbbell", primary: "biceps", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000064", name: "Leg Raise (Captain's Chair)", kind: "bodyweight", equipment: "bodyweight", primary: "core", secondary: ["hip_flexors"]),
        Seed(id: "00000000-0000-4000-8000-000000000065", name: "Pendlay Row (Barbell)", kind: "weight_reps", equipment: "barbell", primary: "back", secondary: ["rear_delts", "biceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000066", name: "Cable Upright Row", kind: "weight_reps", equipment: "cable", primary: "side_delts", secondary: ["traps"]),
        Seed(id: "00000000-0000-4000-8000-000000000067", name: "Incline Bench Press (Smith)", kind: "weight_reps", equipment: "machine", primary: "chest", secondary: ["front_delts", "triceps"]),
        Seed(id: "00000000-0000-4000-8000-000000000068", name: "Bayesian Curl (Cable)", kind: "weight_reps", equipment: "cable", primary: "biceps", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000069", name: "Hammer Curl (Cable)", kind: "weight_reps", equipment: "cable", primary: "biceps", secondary: ["forearms"]),
        Seed(id: "00000000-0000-4000-8000-000000000070", name: "Stairmaster", kind: "duration", equipment: "cardio_machine", primary: "cardio", secondary: []),
        Seed(id: "00000000-0000-4000-8000-000000000071", name: "Incline Walk (Treadmill)", kind: "duration", equipment: "cardio_machine", primary: "cardio", secondary: []),
    ]

    @MainActor
    static func seed(into context: ModelContext) {
        let builtIns = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn }))) ?? []
        let existing = Set(builtIns.map(\.id))
        for seed in all {
            guard let id = UUID(uuidString: seed.id), !existing.contains(id) else { continue }
            context.insert(Exercise(
                id: id, isBuiltIn: true, name: seed.name, kind: seed.kind, equipment: seed.equipment,
                primaryMuscle: seed.primary, secondaryMuscles: seed.secondary
            ))
        }
        try? context.save()
    }
}
