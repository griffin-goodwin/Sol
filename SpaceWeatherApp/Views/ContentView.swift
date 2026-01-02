import SwiftUI

/// Main content view with tab navigation
public struct ContentView: View {
    @State private var viewModel = SpaceWeatherViewModel()
    @State private var selectedTab = 0
    @State private var showNotificationPrompt = false
    @StateObject private var notificationManager = NotificationManager.shared
    
    private let hasPromptedForNotificationsKey = "hasPromptedForNotifications"
    
    public init() {
        // Custom tab bar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.06, alpha: 0.95)
        
        // Unselected state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(white: 0.5, alpha: 1)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(white: 0.5, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        ]
        
        // Selected state
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
                    Label {
                        Text("THE SUN")
                    } icon: {
                        Image(systemName: "sun.max.fill")
                    }
                }
                .tag(0)
            
            ActivityView(viewModel: viewModel)
                .tabItem {
                    Label {
                        Text("ACTIVITY")
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                    }
                }
                .tag(1)
            
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label {
                        Text("SETTINGS")
                    } icon: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                .tag(2)
        }
        .tint(Theme.tabAccent)
        .task {
            // Load data once at startup (stays in RAM)
            await viewModel.loadXRayFlux()
            await viewModel.loadEvents()
            await viewModel.loadFlareProbabilities()
            
            // Check if we should prompt for notifications
            if !UserDefaults.standard.bool(forKey: hasPromptedForNotificationsKey) {
                // Small delay to let the UI settle
                try? await Task.sleep(for: .seconds(1.5))
                showNotificationPrompt = true
            }
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
        .preferredColorScheme(.dark)
    }
}
