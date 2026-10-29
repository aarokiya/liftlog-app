import SwiftData
import SwiftUI

@main
struct LiftLogApp: App {
    let container: ModelContainer
    @State private var auth = AuthService()
    @State private var sync = SyncService()
    @State private var restTimer = RestTimer()
    @State private var health = HealthService()

    init() {
        do {
            container = try ModelContainer(
                for: Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
                Routine.self, RoutineExercise.self, BodyMetric.self, FoodLog.self, WaterLog.self
            )
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        BuiltInExercises.seed(into: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(sync)
                .environment(restTimer)
                .environment(health)
        }
        .modelContainer(container)
    }
}
