import SwiftUI

/// Settings view for app configuration
struct SettingsView: View {
    @Bindable var viewModel: SpaceWeatherViewModel
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingAPIInfo = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationStack {
            List {
                // Notifications Section
                Section {
                    NavigationLink {
                        NotificationSettingsView(notificationManager: notificationManager)
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Theme.accentColor.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "bell.badge.fill")
                                    .foregroundStyle(Theme.accentColor)
                                    .font(.system(size: 16))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notification Settings")
                                    .font(Theme.mono(16, weight: .medium))
                                    .foregroundStyle(Theme.primaryText)
                                
                                if notificationManager.hasAnyNotificationsEnabled {
                                    Text("\(enabledNotificationCount) alert types enabled")
                                        .font(Theme.mono(12))
                                        .foregroundStyle(Theme.secondaryText)
                                } else {
                                    Text("No alerts enabled")
                                        .font(Theme.mono(12))
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    if !notificationManager.isAuthorized && notificationManager.hasAnyNotificationsEnabled {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warning)
                            Text("Notifications disabled in iOS Settings")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.warning)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Theme.cardBackground)
                    }
                } header: {
                    Text("ALERTS")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                } footer: {
                    Text("Get notified about solar flares, geomagnetic storms, and other space weather events.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                
                // API Status Section
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                        Text("Helioviewer API")
                            .font(Theme.mono(14))
                        Spacer()
                        Text("Connected")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.success)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    Button {
                        showingAPIInfo = true
                    } label: {
                        HStack {
                            Label("Learn About the API", systemImage: "info.circle")
                                .font(Theme.mono(14))
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                } header: {
                    Text("DATA SOURCE")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                } footer: {
                    Text("Helioviewer provides free access to solar imagery. No API key required!")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                
                // Data Settings
                Section {
                    HStack {
                        Text("Events Loaded")
                            .font(Theme.mono(14))
                        Spacer()
                        Text("\(viewModel.events.count)")
                            .font(Theme.mono(14, weight: .bold))
                            .foregroundStyle(Theme.accentColor)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    HStack {
                        Text("Current Wavelength")
                            .font(Theme.mono(14))
                        Spacer()
                        Text(viewModel.selectedWavelength.displayName)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        HStack {
                            Text("Refresh Data")
                                .font(Theme.mono(14, weight: .bold))
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(Theme.accentColor)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .foregroundStyle(Theme.accentColor)
                    }
                    .disabled(viewModel.isLoading)
                    .listRowBackground(Theme.cardBackground)
                } header: {
                    Text("DATA")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .headerProminence(.increased)
                .listRowSeparatorTint(Color.white.opacity(0.1))
                
                // SDO Wavelengths Info
                Section {
                    ForEach(SDOWavelength.allCases) { wavelength in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(colorForWavelength(wavelength))
                                .frame(width: 8, height: 8)
                                .shadow(color: colorForWavelength(wavelength).opacity(0.5), radius: 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(wavelength.displayName)
                                    .font(Theme.mono(14, weight: .medium))
                                Text(wavelength.description)
                                    .font(.caption2) // Keep standard font for long reading text
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Theme.cardBackground)
                    }
                } header: {
                    Text("SDO WAVELENGTHS")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                
                // Resources
                Section {
                    LinkRow(title: "Helioviewer.org", icon: "globe", color: Theme.accentSecondary, url: "https://helioviewer.org")
                    LinkRow(title: "API Documentation", icon: "doc.text", color: Theme.accentSecondary, url: "https://api.helioviewer.org/docs/v2/")
                    LinkRow(title: "SDO Mission Website", icon: "sun.max.fill", color: Theme.accentColor, url: "https://sdo.gsfc.nasa.gov")
                    LinkRow(title: "NOAA Space Weather", icon: "antenna.radiowaves.left.and.right", color: Theme.success, url: "https://www.swpc.noaa.gov")
                } header: {
                    Text("RESOURCES")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                
                // App Info
                Section {
                    HStack {
                        Text("Version")
                            .font(Theme.mono(14))
                        Spacer()
                        Text("1.0.0")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    Button {
                        showingAbout = true
                    } label: {
                        Label("About Sol.", systemImage: "sparkles")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.primaryText)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    LinkRow(title: "Privacy Policy", icon: "hand.raised.fill", color: Theme.accentSecondary, url: "https://github.com/griffin-goodwin/Sol/blob/main/PRIVACY_POLICY.md")
                } header: {
                    Text("ABOUT")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(Theme.mono(32, weight: .black))
                        .tracking(3)
                        .foregroundStyle(Theme.settingsTitleGradient)
                        .shadow(color: Color.white.opacity(0.2), radius: 6, x: 0, y: 0)
                }
            }
            .sheet(isPresented: $showingAPIInfo) {
                APIInfoSheet()
            }
            .sheet(isPresented: $showingAbout) {
                AboutSheet()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient)
        }
        .preferredColorScheme(.dark)
    }
    
    private func colorForWavelength(_ wavelength: SDOWavelength) -> Color {
        switch wavelength.color {
        case "green": return .green
        case "teal": return .teal
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "blue": return .blue
        case "pink": return .pink
        case "gray": return .gray
        default: return .white
        }
    }
    
    private var enabledNotificationCount: Int {
        var count = 0
        let prefs = notificationManager.preferences
        if prefs.xClassFlares { count += 1 }
        if prefs.mClassFlares { count += 1 }
        if prefs.cClassFlares { count += 1 }
        if prefs.geomagneticStorms { count += 1 }
        if prefs.radiationStorms { count += 1 }
        if prefs.radioBlackouts { count += 1 }
        if prefs.protonEvents { count += 1 }
        if prefs.earthDirectedCME { count += 1 }
        if prefs.elevatedFlareProbability { count += 1 }
        return count
    }
}

// MARK: - Helper Views

struct LinkRow: View {
    let title: String
    let icon: String
    let color: Color
    let url: String
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title)
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .listRowBackground(Theme.cardBackground)
    }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            // Authorization status
            if !notificationManager.isAuthorized {
                Section {
                    Button {
                        Task {
                            await notificationManager.requestAuthorization()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell.slash.fill")
                                .foregroundStyle(Theme.warning)
                            Text("Enable Notifications")
                                .font(Theme.mono(14, weight: .bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                } footer: {
                    Text("Tap to request notification permission. You may need to enable notifications in iOS Settings.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            
            // Solar Flares
            Section {
                Toggle(isOn: $notificationManager.preferences.xClassFlares) {
                    NotificationRow(
                        icon: "bolt.fill",
                        iconColor: .red,
                        title: "X-Class Flares",
                        subtitle: "Extreme intensity (rare)"
                    )
                }
                .listRowBackground(Theme.cardBackground)
                
                Toggle(isOn: $notificationManager.preferences.mClassFlares) {
                    NotificationRow(
                        icon: "bolt.fill",
                        iconColor: .orange,
                        title: "M-Class Flares",
                        subtitle: "High intensity"
                    )
                }
                .listRowBackground(Theme.cardBackground)
                
                Toggle(isOn: $notificationManager.preferences.cClassFlares) {
                    NotificationRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "C-Class Flares",
                        subtitle: "Moderate intensity (frequent)"
                    )
                }
                .listRowBackground(Theme.cardBackground)
            } header: {
                Text("SOLAR FLARES")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            } footer: {
                Text("X-class flares are the most powerful and can affect Earth. M-class are moderate, C-class are minor.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            
            // Geomagnetic & Radiation
            Section {
                Toggle(isOn: $notificationManager.preferences.geomagneticStorms) {
                    NotificationRow(
                        icon: "globe.americas.fill",
                        iconColor: .purple,
                        title: "Geomagnetic Storms",
                        subtitle: "G1+ storm alerts and watches"
                    )
                }
                .listRowBackground(Theme.cardBackground)
                
                Toggle(isOn: $notificationManager.preferences.radiationStorms) {
                    NotificationRow(
                        icon: "shield.fill",
                        iconColor: .green,
                        title: "Radiation Storms",
                        subtitle: "Solar radiation events"
                    )
                }
                .listRowBackground(Theme.cardBackground)
                
                Toggle(isOn: $notificationManager.preferences.radioBlackouts) {
                    NotificationRow(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: .blue,
                        title: "Radio Blackouts",
                        subtitle: "HF radio communication impacts"
                    )
                }
                .listRowBackground(Theme.cardBackground)
            } header: {
                Text("SPACE WEATHER IMPACTS")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            
            // CME & Particles
            Section {
                Toggle(isOn: $notificationManager.preferences.earthDirectedCME) {
                    NotificationRow(
                        icon: "sun.max.fill",
                        iconColor: .orange,
                        title: "Earth-Directed CMEs",
                        subtitle: "Coronal mass ejections toward Earth"
                    )
                }
                .listRowBackground(Theme.cardBackground)
                
                Toggle(isOn: $notificationManager.preferences.protonEvents) {
                    NotificationRow(
                        icon: "atom",
                        iconColor: .cyan,
                        title: "Proton Events",
                        subtitle: "High-energy particle events"
                    )
                }
                .listRowBackground(Theme.cardBackground)
            } header: {
                Text("SOLAR ERUPTIONS")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            
            // Forecasts
            Section {
                Toggle(isOn: $notificationManager.preferences.elevatedFlareProbability) {
                    NotificationRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .pink,
                        title: "Elevated Flare Probability",
                        subtitle: "When M/X flare risk increases significantly"
                    )
                }
                .listRowBackground(Theme.cardBackground)
            } header: {
                Text("FORECASTS")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            } footer: {
                Text("Get notified when SWPC raises the flare probability above threshold levels.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            
            // Quick Actions
            Section {
                Button("Enable All Alerts") {
                    withAnimation {
                        notificationManager.preferences.xClassFlares = true
                        notificationManager.preferences.mClassFlares = true
                        notificationManager.preferences.cClassFlares = true
                        notificationManager.preferences.geomagneticStorms = true
                        notificationManager.preferences.radiationStorms = true
                        notificationManager.preferences.radioBlackouts = true
                        notificationManager.preferences.protonEvents = true
                        notificationManager.preferences.earthDirectedCME = true
                        notificationManager.preferences.elevatedFlareProbability = true
                    }
                }
                .font(Theme.mono(14))
                .listRowBackground(Theme.cardBackground)
                
                Button("Disable All Alerts") {
                    withAnimation {
                        notificationManager.preferences.xClassFlares = false
                        notificationManager.preferences.mClassFlares = false
                        notificationManager.preferences.cClassFlares = false
                        notificationManager.preferences.geomagneticStorms = false
                        notificationManager.preferences.radiationStorms = false
                        notificationManager.preferences.radioBlackouts = false
                        notificationManager.preferences.protonEvents = false
                        notificationManager.preferences.earthDirectedCME = false
                        notificationManager.preferences.elevatedFlareProbability = false
                    }
                }
                .foregroundStyle(Theme.danger)
                .font(Theme.mono(14))
                .listRowBackground(Theme.cardBackground)
                
                Button("Essential Only") {
                    withAnimation {
                        notificationManager.preferences.xClassFlares = true
                        notificationManager.preferences.mClassFlares = true
                        notificationManager.preferences.cClassFlares = false
                        notificationManager.preferences.geomagneticStorms = true
                        notificationManager.preferences.radiationStorms = false
                        notificationManager.preferences.radioBlackouts = false
                        notificationManager.preferences.protonEvents = false
                        notificationManager.preferences.earthDirectedCME = true
                        notificationManager.preferences.elevatedFlareProbability = false
                    }
                }
                .font(Theme.mono(14))
                .listRowBackground(Theme.cardBackground)
            } header: {
                Text("QUICK SETTINGS")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            
            // Background Info
            Section {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.secondaryText)
                    VStack(alignment: .leading) {
                        Text("Background Refresh")
                            .font(Theme.mono(14))
                        Text("Checks for new alerts every 15 minutes when enabled")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .listRowBackground(Theme.cardBackground)
                
                Button {
                    notificationManager.sendTestNotification()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(Theme.accentColor)
                        Text("Send Test Notification")
                            .font(Theme.mono(14))
                        Spacer()
                        Text("Tap to test")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .disabled(!notificationManager.isAuthorized)
                .listRowBackground(Theme.cardBackground)
            } footer: {
                Text("Background refresh requires iOS system permission. Battery impact is minimal.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.mono(14, weight: .medium))
                Text(subtitle)
                    .font(.caption) // Keeping standard font for readability
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - API Info Sheet

struct APIInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "sun.max.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.accentColor)
                            .shadow(color: Theme.accentColor.opacity(0.5), radius: 20)
                        
                        Text("Helioviewer API")
                            .font(Theme.mono(24, weight: .bold))
                        
                        Text("Free Solar Data Access")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("FEATURES")
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        
                        VStack(spacing: 0) {
                            FeatureRow(icon: "key.slash", text: "No API key required", color: Theme.success)
                            Divider().background(Color.white.opacity(0.1))
                            FeatureRow(icon: "photo.stack", text: "Solar imagery from SDO, SOHO, and more", color: Theme.accentSecondary)
                            Divider().background(Color.white.opacity(0.1))
                            FeatureRow(icon: "calendar", text: "Historical data back to 2010", color: .purple)
                            Divider().background(Color.white.opacity(0.1))
                            FeatureRow(icon: "sparkles", text: "Real-time solar events", color: Theme.accentColor)
                            Divider().background(Color.white.opacity(0.1))
                            FeatureRow(icon: "video", text: "Create custom movies", color: Theme.danger)
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // SDO Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ABOUT SDO")
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The Solar Dynamics Observatory (SDO) is a NASA mission that studies the Sun. It captures images of the Sun in multiple wavelengths, revealing different layers and features of the solar atmosphere.")
                            
                            Text("SDO takes images every 12 seconds and has been operating since 2010, providing an unprecedented view of solar activity.")
                        }
                        .font(.subheadline) // Keep standard font for reading blocks
                        .foregroundStyle(Theme.secondaryText)
                        .padding(16)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            if let url = URL(string: "https://helioviewer.org") {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "globe")
                                Text("Visit Helioviewer.org")
                            }
                            .font(Theme.mono(14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        
                        Button {
                            if let url = URL(string: "https://api.helioviewer.org/docs/v2/") {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("View API Documentation")
                            }
                            .font(Theme.mono(14, weight: .bold))
                            .foregroundStyle(Theme.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.backgroundGradient)
            .navigationTitle("API Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(Theme.accentColor)
                }
            }
        }
    }
}

// MARK: - About Sheet

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "sun.max.trianglebadge.exclamationmark.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.accentColor)
                            .shadow(color: Theme.accentColor.opacity(0.5), radius: 20)
                        
                        Text("Sol.")
                            .font(Theme.mono(28, weight: .black))
                            .tracking(2)
                        
                        Text("Real-Time Space Weather Monitoring")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 16) {
                        Text("MISSION")
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sol. provides real-time access to solar imagery and space weather alerts from NASA's Solar Dynamics Observatory and NOAA's Space Weather Prediction Center.")
                            
                            Text("Stay informed about solar flares, coronal mass ejections, and geomagnetic storms that can affect Earth's technology, communications, and power grids.")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(16)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // Credits
                    VStack(alignment: .leading, spacing: 16) {
                        Text("DATA SOURCES")
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        
                        VStack(spacing: 0) {
                            CreditRow(title: "NOAA SWPC", subtitle: "Space Weather Prediction Center")
                            Divider().background(Color.white.opacity(0.1))
                            CreditRow(title: "Helioviewer", subtitle: "Solar imagery API")
                            Divider().background(Color.white.opacity(0.1))
                            CreditRow(title: "NASA SDO", subtitle: "Solar Dynamics Observatory")
                            Divider().background(Color.white.opacity(0.1))
                            CreditRow(title: "NASA SOHO", subtitle: "LASCO Coronagraph")
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // Legal
                    VStack(alignment: .leading, spacing: 16) {
                        Text("LEGAL")
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sol. does not collect any personal data. Space weather data is provided by public government sources.")
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                            
                            Text("© 2026 Sol. All rights reserved.")
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .padding(16)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(20)
            }
            .background(Theme.backgroundGradient)
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(Theme.accentColor)
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(Theme.mono(13))
            
            Spacer()
        }
        .padding(16)
    }
}

struct CreditRow: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.mono(14, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(16)
    }
}

#Preview {
    SettingsView(viewModel: SpaceWeatherViewModel())
}
