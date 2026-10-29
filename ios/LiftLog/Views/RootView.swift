import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(HealthService.self) private var health

    var body: some View {
        TabView {
            WorkoutTab().tabItem { Label("Workout", systemImage: "dumbbell") }
            FoodView().tabItem { Label("Food", systemImage: "fork.knife") }
            RoutinesView().tabItem { Label("Routines", systemImage: "list.bullet.rectangle") }
            StatsView().tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task(id: auth.userId) { await sync.run(context: context, auth: auth) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !ProcessInfo.processInfo.arguments.contains("-uiDemo") else { return }
            Task {
                await health.sync(context: context)
                await sync.run(context: context, auth: auth)
            }
        }
        .onOpenURL { url in Task { await auth.handle(url: url) } }
    }
}
