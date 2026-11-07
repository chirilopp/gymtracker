import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }
    // Приложение открыто: сигнал (звук и вибрацию) подаёт сам таймер, баннер не нужен.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}

@main
struct GymTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Color.gRed)
                .onChange(of: phase) { _, new in
                    if new == .active { store.rest.sync() }
                    if new == .background || new == .inactive { store.writeNow() }
                }
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        TabView {
            NavigationStack { HomeView().routeDestinations() }
                .tabItem { Label("Тренировки", systemImage: "calendar") }
            NavigationStack { ExercisesView(pickMode: false, onPick: { _ in }).routeDestinations() }
                .tabItem { Label("Упражнения", systemImage: "list.bullet") }
            NavigationStack { ProgressScreen(initial: nil).routeDestinations() }
                .tabItem { Label("Прогресс", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationStack { SettingsView().routeDestinations() }
                .tabItem { Label("Ещё", systemImage: "gearshape") }
        }
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                Text(t)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.gCard2, in: Capsule())
                    .padding(.bottom, 100)
                    .transition(.opacity)
                    .task(id: t) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        if store.toast == t { store.toast = nil }
                    }
            }
        }
        .animation(.default, value: store.toast)
    }
}

extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }
}
