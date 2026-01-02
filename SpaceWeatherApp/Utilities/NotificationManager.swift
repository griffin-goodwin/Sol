import Foundation
import UserNotifications
import BackgroundTasks

// MARK: - Notification Preferences

/// Individual notification settings for each event type/threshold
struct NotificationPreferences: Codable {
    // Flare alerts by class
    var xClassFlares: Bool = true       // X-class (extreme)
    var mClassFlares: Bool = true       // M-class (high)
    var cClassFlares: Bool = false      // C-class (moderate) - off by default
    
    // SWPC Alerts
    var geomagneticStorms: Bool = true  // G1+ storms
    var radiationStorms: Bool = true    // S1+ radiation events
    var radioBlackouts: Bool = true     // R1+ radio blackouts
    
    // Proton events
    var protonEvents: Bool = false      // 10 MeV proton events
    
    // CME alerts
    var earthDirectedCME: Bool = true   // CMEs potentially affecting Earth
    
    // Forecast changes
    var elevatedFlareProbability: Bool = false  // When M/X probability increases significantly
    
    static let `default` = NotificationPreferences()
}

// MARK: - Notification Manager

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var preferences: NotificationPreferences {
        didSet {
            savePreferences()
        }
    }
    
    // Track seen events to avoid duplicate notifications
    private var seenEventIds: Set<String> = []
    private let seenEventsKey = "seenNotificationEventIds"
    private let preferencesKey = "notificationPreferences"
    
    // Background task identifier
    static let backgroundTaskIdentifier = "com.griffingoodwin.sol.refresh"
    
    override init() {
        // Load preferences
        if let data = UserDefaults.standard.data(forKey: preferencesKey),
           let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            self.preferences = prefs
        } else {
            self.preferences = .default
        }
        
        super.init()
        
        loadSeenEventIds()
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            // Request full notification permissions (not provisional - those deliver quietly)
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("❌ Notification authorization error: \(error)")
            return false
        }
    }
    
    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                self.isAuthorized = status == .authorized || status == .provisional
            }
        }
    }
    
    // MARK: - Preferences Persistence
    
    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
    }
    
    private func loadSeenEventIds() {
        if let ids = UserDefaults.standard.array(forKey: seenEventsKey) as? [String] {
            seenEventIds = Set(ids)
        }
        // Prune old entries (keep last 500)
        if seenEventIds.count > 500 {
            seenEventIds = Set(Array(seenEventIds).suffix(500))
            saveSeenEventIds()
        }
    }
    
    private func saveSeenEventIds() {
        UserDefaults.standard.set(Array(seenEventIds), forKey: seenEventsKey)
    }
    
    // MARK: - Check if Notifications Enabled
    
    var hasAnyNotificationsEnabled: Bool {
        preferences.xClassFlares || 
        preferences.mClassFlares || 
        preferences.cClassFlares ||
        preferences.geomagneticStorms ||
        preferences.radiationStorms ||
        preferences.radioBlackouts ||
        preferences.protonEvents ||
        preferences.earthDirectedCME ||
        preferences.elevatedFlareProbability
    }
    
    // MARK: - Process Events for Notifications
    
    /// Mark events as seen without sending notifications (called on app launch)
    func markEventsAsSeen(_ events: [SpaceWeatherEvent]) {
        for event in events {
            seenEventIds.insert(event.id)
        }
        saveSeenEventIds()
        print("📝 Marked \(events.count) existing events as seen")
    }
    
    func processEventsForNotifications(_ events: [SpaceWeatherEvent]) {
        guard isAuthorized && hasAnyNotificationsEnabled else { return }
        
        // Only notify about events from the last hour (to avoid old event spam)
        let oneHourAgo = Date().addingTimeInterval(-3600)
        
        for event in events {
            // Skip if we've already notified about this event
            guard !seenEventIds.contains(event.id) else { continue }
            
            // Skip events older than 1 hour - they're not "new"
            guard event.date > oneHourAgo else {
                // Still mark as seen so we don't notify later
                seenEventIds.insert(event.id)
                continue
            }
            
            // Check if notification should be sent based on preferences
            if shouldNotify(for: event) {
                scheduleNotification(for: event)
                seenEventIds.insert(event.id)
            }
        }
        
        saveSeenEventIds()
    }
    
    private func shouldNotify(for event: SpaceWeatherEvent) -> Bool {
        switch event.type {
        case .solarFlare:
            // Check flare class from title
            let title = event.title.uppercased()
            if title.contains("X") && (event.severity == .extreme || title.contains("X-CLASS")) {
                return preferences.xClassFlares
            }
            if event.severity == .high || title.contains("M") {
                return preferences.mClassFlares
            }
            if event.severity == .moderate || title.contains("C") {
                return preferences.cClassFlares
            }
            return false
            
        case .geomagneticStorm:
            return preferences.geomagneticStorms
            
        case .radiationBeltEnhancement, .solarEnergeticParticle:
            return preferences.radiationStorms || preferences.protonEvents
            
        case .cme:
            return preferences.earthDirectedCME
            
        default:
            return false
        }
    }
    
    private func scheduleNotification(for event: SpaceWeatherEvent) {
        let content = UNMutableNotificationContent()
        
        // Set title and body based on event type with detailed info
        switch event.type {
        case .solarFlare:
            // Extract flare class from title (e.g., "Flare: M5.2" or "Solar Flare: X1.0")
            let flareClass = extractFlareClass(from: event.title) ?? event.severity.rawValue
            content.title = "🌞 \(flareClass) Solar Flare"
            content.body = buildFlareBody(event: event, flareClass: flareClass)
            if event.severity == .extreme {
                content.sound = .defaultCritical
            } else {
                content.sound = .default
            }
            
        case .geomagneticStorm:
            content.title = "🌍 Geomagnetic Storm Alert"
            content.body = buildGeomagneticBody(event: event)
            content.sound = .default
            
        case .cme:
            content.title = "☀️ Coronal Mass Ejection"
            content.body = buildCMEBody(event: event)
            content.sound = .default
            
        case .radiationBeltEnhancement, .solarEnergeticParticle:
            content.title = "⚠️ Radiation Alert"
            content.body = event.title + (event.details.isEmpty ? "" : "\n\(event.details)")
            content.sound = .default
            
        default:
            content.title = "Space Weather Alert"
            content.body = event.title
            content.sound = .default
        }
        
        // Add category for actions
        content.categoryIdentifier = "SPACE_WEATHER_ALERT"
        content.userInfo = ["eventId": event.id, "eventType": event.type.rawValue]
        
        // Add thread identifier for grouping
        content.threadIdentifier = event.type.rawValue
        
        // Schedule immediately (already happened)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            } else {
                print("✅ Scheduled notification for: \(event.title)")
            }
        }
    }
    
    // MARK: - Notification Content Helpers
    
    private func extractFlareClass(from title: String) -> String? {
        // Pattern matches X1.5, M5.2, C3.4, etc.
        let pattern = #"([XMCBA]\d+\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let range = Range(match.range(at: 1), in: title) {
            return String(title[range]).uppercased()
        }
        return nil
    }
    
    private func buildFlareBody(event: SpaceWeatherEvent, flareClass: String) -> String {
        var body = ""
        
        // Add severity description
        switch event.severity {
        case .extreme:
            body = "Extreme solar flare detected! May cause radio blackouts and GPS disruption."
        case .high:
            body = "Strong solar flare detected. Possible radio interference."
        case .moderate:
            body = "Moderate solar flare detected."
        case .weak:
            body = "Minor solar flare detected."
        case .none:
            body = "Solar flare detected."
        }
        
        // Add location if available
        if let x = event.hpcX, let y = event.hpcY {
            let location = x > 0 ? "eastern" : "western"
            body += " Location: \(location) solar hemisphere."
        }
        
        // Add time
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        body += " Time: \(formatter.string(from: event.date)) UTC"
        
        return body
    }
    
    private func buildGeomagneticBody(event: SpaceWeatherEvent) -> String {
        var body = event.title
        
        // Add impact info based on storm level
        if event.title.contains("G3") || event.title.contains("K-index of 7") {
            body += "\n⚠️ Strong storm - possible power grid issues, satellite drag, aurora visible at mid-latitudes"
        } else if event.title.contains("G2") || event.title.contains("K-index of 6") {
            body += "\n⚡ Moderate storm - aurora visible at higher latitudes, possible GPS issues"
        } else if event.title.contains("G1") || event.title.contains("K-index of 5") {
            body += "\n🌌 Minor storm - aurora possible at high latitudes"
        }
        
        return body
    }
    
    private func buildCMEBody(event: SpaceWeatherEvent) -> String {
        var body = event.title
        
        // Try to extract speed from details
        if event.details.contains("km/s") {
            let pattern = #"(\d+)\s*km/s"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: event.details, range: NSRange(event.details.startIndex..., in: event.details)),
               let range = Range(match.range(at: 1), in: event.details) {
                let speed = String(event.details[range])
                body += "\nSpeed: \(speed) km/s"
                
                if let speedInt = Int(speed), speedInt > 1000 {
                    body += " ⚠️ Fast CME - may cause geomagnetic storm"
                }
            }
        }
        
        return body
    }
    
    // MARK: - Flare Probability Notifications
    
    func checkFlareProbabilityChange(old: FlareProbabilityForecast, new: FlareProbabilityForecast) {
        guard preferences.elevatedFlareProbability && isAuthorized else { return }
        
        // Notify if X-class probability jumps significantly
        if new.xClassProbability >= 25 && old.xClassProbability < 25 {
            sendProbabilityAlert(className: "X", probability: new.xClassProbability)
        }
        // Notify if M-class probability jumps significantly
        else if new.mClassProbability >= 60 && old.mClassProbability < 60 {
            sendProbabilityAlert(className: "M", probability: new.mClassProbability)
        }
    }
    
    private func sendProbabilityAlert(className: String, probability: Int) {
        let content = UNMutableNotificationContent()
        content.title = "📈 Elevated Flare Risk"
        content.body = "\(className)-class flare probability now at \(probability)% for the next 24 hours"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "prob-\(className)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Background Task Registration
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Fetch no earlier than 15 minutes from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background refresh scheduled")
        } catch {
            print("⚠️ Could not schedule background refresh: \(error)")
        }
    }
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleBackgroundRefresh()
        
        // Create a task to fetch alerts
        let fetchTask = Task {
            do {
                let swpcService = SWPCService()
                
                // Fetch both SWPC alerts and GOES flares
                async let alertsTask = swpcService.fetchUnifiedAlerts()
                async let flaresTask = swpcService.fetchUnifiedFlares()
                
                let (alerts, flares) = try await (alertsTask, flaresTask)
                let allEvents = alerts + flares
                
                await MainActor.run {
                    self.processEventsForNotifications(allEvents)
                }
                
                task.setTaskCompleted(success: true)
            } catch {
                print("⚠️ Background fetch failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
        
        // Handle expiration
        task.expirationHandler = {
            fetchTask.cancel()
        }
    }
    
    // MARK: - Clear Notifications
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func clearSeenEvents() {
        seenEventIds.removeAll()
        saveSeenEventIds()
    }
    
    // MARK: - Test Notification
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🌞 Test Solar Flare Alert"
        content.body = "This is a test notification from Sol. If you see this, notifications are working!"
        content.sound = .default
        content.categoryIdentifier = "SPACE_WEATHER_ALERT"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send test notification: \(error)")
            } else {
                print("✅ Test notification scheduled")
            }
        }
    }
}

// MARK: - Notification Categories

extension NotificationManager {
    func setupNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "Dismiss",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "SPACE_WEATHER_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
