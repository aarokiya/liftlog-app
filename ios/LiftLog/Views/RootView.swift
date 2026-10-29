import SwiftData
import SwiftUI

struct RootView: View {
    private enum Page: Hashable { case workout, food, routines, stats, settings }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(HealthService.self) private var health
    @Environment(Reminders.self) private var reminders
    @State private var tab = Page.workout

    var body: some View {
        TabView(selection: $tab) {
            WorkoutTab().tabItem { Label("Workout", systemImage: "dumbbell") }.tag(Page.workout)
            FoodView().tabItem { Label("Food", systemImage: "fork.knife") }.tag(Page.food)
            RoutinesView().tabItem { Label("Routines", systemImage: "list.bullet.rectangle") }.tag(Page.routines)
            StatsView().tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }.tag(Page.stats)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(Page.settings)
        }
        .task(id: auth.userId) { await sync.run(context: context, auth: auth) }
        .onChange(of: scenePhase) { _, phase in
            guard !ProcessInfo.processInfo.arguments.contains("-uiDemo") else { return }
            if phase == .active {
                Task {
                    await health.sync(context: context)
                    await sync.run(context: context, auth: auth)
                    reminders.refresh(context: context, health: health)
                }
            } else if phase == .background {
                reminders.refresh(context: context, health: health, rereadHealth: false)
            }
        }
        .onChange(of: reminders.openFood, initial: true) { _, open in
            guard open else { return }
            tab = .food
            reminders.openFood = false
        }
        .onOpenURL { url in Task { await auth.handle(url: url) } }
    }
}
