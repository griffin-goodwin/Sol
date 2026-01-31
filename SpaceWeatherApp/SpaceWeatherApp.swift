import SwiftUI
import BackgroundTasks

@main
struct SpaceWeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                // Schedule background refresh when app goes to background
                Task { @MainActor in
                    if NotificationManager.shared.hasAnyNotificationsEnabled {
                        NotificationManager.shared.scheduleBackgroundRefresh()
                        print("📱 App entered background - scheduled refresh")
                    }
                }
            case .active:
                // Check notification authorization when app becomes active
                Task { @MainActor in
                    NotificationManager.shared.checkAuthorization()
                    print("📱 App became active")
                }
            default:
                break
            }
        }
    }
}

// MARK: - App Delegate for Background Tasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Register background tasks - must happen before app finishes launching
        // and must be on main thread (which we are during didFinishLaunching)
        NotificationManager.shared.registerBackgroundTasks()

        // Setup notification categories on main actor
        Task { @MainActor in
            NotificationManager.shared.setupNotificationCategories()
        }

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        return true
    }
}

// MARK: - Notification Delegate (separate to avoid actor isolation issues)

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let eventId = userInfo["eventId"] as? String {
            // Could navigate to specific event here
            print("User tapped notification for event: \(eventId)")
        }
        
        completionHandler()
    }
}
