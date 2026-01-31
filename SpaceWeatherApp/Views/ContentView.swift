import SwiftUI
import StoreKit

/// Main content view with tab navigation
public struct ContentView: View {
    @State private var viewModel = SpaceWeatherViewModel()
    @State private var selectedTab = 0
    @State private var showNotificationPrompt = false
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var hasLaunched = false
    @Environment(\.requestReview) private var requestReview
    
    private let hasPromptedForNotificationsKey = "hasPromptedForNotifications"
    
    public init() {
        // Custom tab bar appearance with enhanced styling
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.05, alpha: 0.98)
        
        // Add subtle top border
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        
        // Unselected state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(white: 0.45, alpha: 1)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        ]
        
        // Selected state with enhanced visibility
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Theme.tabAccent)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.tabAccent),
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        ]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            SDOImageView(viewModel: viewModel)
                .tabItem {
                    Label("IMAGES", systemImage: "sun.max.fill")
                }
                .tag(0)

            ActivityView(viewModel: viewModel)
                .tabItem {
                    Label("ACTIVITY", systemImage: "waveform.path.ecg")
                }
                .tag(1)

            AuroraView()
                .tabItem {
                    Label("AURORA", systemImage: "globe.americas.fill")
                }
                .tag(2)

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("SETTINGS", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(selectedTab == 0 ? viewModel.imageTabAccentColor : Theme.tabAccent)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .task {
            // Load data once at startup (stays in RAM)
            await viewModel.loadXRayFlux()
            await viewModel.loadEvents()
            await viewModel.loadFlareProbabilities()
            
            // Mark existing events as "seen" so we don't notify about old events
            NotificationManager.shared.markEventsAsSeen(viewModel.events)
            
            // Check if we should prompt for notifications
            if !UserDefaults.standard.bool(forKey: hasPromptedForNotificationsKey) {
                // Small delay to let the UI settle
                try? await Task.sleep(for: .seconds(1.5))
                showNotificationPrompt = true
            }

            // Mark that initial launch tasks completed to avoid duplicate refresh
            hasLaunched = true
        }
        .alert("Enable Notifications?", isPresented: $showNotificationPrompt) {
            Button("Enable") {
                Task {
                    _ = await notificationManager.requestAuthorization()
                    UserDefaults.standard.set(true, forKey: hasPromptedForNotificationsKey)
                }
            }
            Button("Not Now", role: .cancel) {
                UserDefaults.standard.set(true, forKey: hasPromptedForNotificationsKey)
            }
        } message: {
            Text("Get alerts for solar flares, geomagnetic storms, and other space weather events that could affect Earth.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            ReviewManager.recordAppSession()

            // Only perform a full refresh when the app is reopened after the initial launch
            if hasLaunched {
                Task {
                    await viewModel.refresh()
                    try? await Task.sleep(for: .seconds(2))
                    ReviewManager.requestReviewIfAppropriate(using: requestReview)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
