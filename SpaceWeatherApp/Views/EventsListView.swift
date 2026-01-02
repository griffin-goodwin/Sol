import SwiftUI

/// List view showing all space weather events
struct EventsListView: View {
    @Bindable var viewModel: SpaceWeatherViewModel
    @State private var showingFilters = false
    
    // Filter events by selected types
    private var filteredEventsList: [SpaceWeatherEvent] {
        return viewModel.events.filter { event in
            viewModel.overlayEventTypes.contains(event.type)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date and time controls at top
                dateControlsHeader
                
                Group {
                    if viewModel.isLoading && viewModel.events.isEmpty {
                        LoadingView()
                    } else if let error = viewModel.errorMessage, viewModel.events.isEmpty {
                        ErrorView(message: error) {
                            Task { await viewModel.refresh() }
                        }
                    } else if filteredEventsList.isEmpty {
                        EmptyStateView(hasFilters: !viewModel.overlayEventTypes.isEmpty) {
                            viewModel.overlayEventTypes = Set(SpaceWeatherEventType.allCases)
                        }
                    } else {
                        eventsList
                    }
                }
            }
            .background(Theme.backgroundGradient)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EVENTS")
                        .font(Theme.mono(22, weight: .black))
                        .tracking(3)
                        .foregroundStyle(Theme.activityTitleGradient)
                        .shadow(color: Theme.accentSecondary.opacity(0.4), radius: 8, x: 0, y: 0)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingFilters = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("\(viewModel.overlayEventTypes.count)")
                                .font(Theme.mono(12))
                        }
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showingFilters) {
                EventsFilterSheet(viewModel: viewModel)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
    
    // MARK: - Date Controls Header
    
    private var dateControlsHeader: some View {
        VStack(spacing: 12) {
            // Time range picker
            HStack {
                Text("Time Range")
                    .font(Theme.mono(14))
                    .foregroundStyle(.white.opacity(0.7))
                
                Spacer()
                
                Picker("", selection: $viewModel.overlayTimeRangeHours) {
                    Text("6 hours").tag(6.0)
                    Text("12 hours").tag(12.0)
                    Text("1 day").tag(24.0)
                    Text("3 days").tag(72.0)
                    Text("7 days").tag(168.0)
                }
                .pickerStyle(.menu)
                .tint(.orange)
            }
            
            // Event count
            Text("\(filteredEventsList.count) events in \(formatTimeRange(viewModel.overlayTimeRangeHours))")
                .font(Theme.mono(12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding()
        .background(Theme.cardBackground)
    }
    
    private func formatTimeRange(_ hours: Double) -> String {
        if hours < 24 {
            return "\(Int(hours)) hours"
        } else if hours == 24 {
            return "1 day"
        } else {
            return "\(Int(hours / 24)) days"
        }
    }
    
    private var eventsList: some View {
        List {
            ForEach(filteredEventsList) { event in
                NavigationLink(destination: EventDetailView(event: event, viewModel: viewModel)) {
                    EventRowView(event: event)
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Event Row View

struct EventRowView: View {
    let event: SpaceWeatherEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Event type icon - use white with colored background
            Image(systemName: event.type.icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(colorForType(event.type).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(Theme.mono(16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                // Show more useful details based on event type
                Text(eventSubtitle)
                    .font(Theme.mono(14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    SeverityBadge(severity: event.severity)
                    
                    // Show coordinates if available
                    if let x = event.hpcX, let y = event.hpcY {
                        Text(formatCoordinates(x: x, y: y))
                            .font(Theme.mono(10))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(Theme.mono(12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var eventSubtitle: String {
        // Show type-specific info instead of generic details
        switch event.type {
        case .solarFlare:
            // Details usually has class info
            return event.details
        case .activeRegion:
            if let x = event.hpcX, let y = event.hpcY {
                let hemisphere = y >= 0 ? "N" : "S"
                let diskPos = x >= 0 ? "E" : "W"
                return "\(hemisphere) hemisphere, \(diskPos) limb · \(event.details)"
            }
            return event.details
        case .cme:
            return "Coronal Mass Ejection · \(event.details)"
        case .sunspot:
            return "Sunspot group · \(event.details)"
        default:
            return event.details
        }
    }
    
    private func formatCoordinates(x: Double, y: Double) -> String {
        // Format as heliographic-style coordinates
        let xDir = x >= 0 ? "E" : "W"
        let yDir = y >= 0 ? "N" : "S"
        return "\(yDir)\(abs(Int(y / 10)))° \(xDir)\(abs(Int(x / 10)))°"
    }
    
    private func colorForType(_ type: SpaceWeatherEventType) -> Color {
        switch type.color {
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        case "blue": return .blue
        case "green": return .green
        case "cyan": return .cyan
        default: return .gray
        }
    }
}

// MARK: - Severity Badge

struct SeverityBadge: View {
    let severity: SpaceWeatherEvent.EventSeverity
    
    var body: some View {
        // Only show badge if severity has a label (i.e., for flares)
        if severity != .none {
            Text(severity.rawValue)
                .font(Theme.mono(12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(severityColor.opacity(0.2))
                .foregroundStyle(severityColor)
                .clipShape(Capsule())
        }
    }
    
    private var severityColor: Color {
        switch severity.color {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Events Filter Sheet (matches Solar overlay filter)

struct EventsFilterSheet: View {
    @Bindable var viewModel: SpaceWeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let timeRangeOptions: [(label: String, hours: Double)] = [
        ("6 hours", 6),
        ("1 day", 24),
        ("3 days", 72),
        ("7 days", 168)
    ]
    
    // Event types we support (from HEK and/or SWPC)
    private let supportedEventTypes: [SpaceWeatherEventType] = [
        .activeRegion,
        .solarFlare,
        .cme,
        .geomagneticStorm,
        .radiationBeltEnhancement
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Time Range", selection: $viewModel.overlayTimeRangeHours) {
                        ForEach(timeRangeOptions, id: \.hours) { option in
                            Text(option.label).tag(option.hours)
                        }
                    }
                } header: {
                    Text("Time Window")
                } footer: {
                    Text("Show events within \(formatTimeRange(viewModel.overlayTimeRangeHours)) of selected time.")
                }
                
                Section {
                    ForEach(supportedEventTypes) { type in
                        Toggle(isOn: Binding(
                            get: { viewModel.overlayEventTypes.contains(type) },
                            set: { isOn in
                                if isOn {
                                    viewModel.overlayEventTypes.insert(type)
                                } else {
                                    viewModel.overlayEventTypes.remove(type)
                                }
                            }
                        )) {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundStyle(colorForType(type))
                                Text(type.displayName)
                            }
                        }
                    }
                } header: {
                    Text("Event Types")
                } footer: {
                    Text("Events from HEK (solar) and SWPC (alerts).")
                }
                
                Section {
                    Button("Show All") {
                        viewModel.overlayEventTypes = Set(supportedEventTypes)
                    }
                    Button("Hide All") {
                        viewModel.overlayEventTypes = []
                    }
                }
            }
            .navigationTitle("Filter Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func formatTimeRange(_ hours: Double) -> String {
        if hours < 24 {
            return "\(Int(hours)) hours"
        } else if hours == 24 {
            return "1 day"
        } else {
            return "\(Int(hours / 24)) days"
        }
    }
    
    private func colorForType(_ type: SpaceWeatherEventType) -> Color {
        switch type {
        case .cme: return .orange
        case .geomagneticStorm: return .purple
        case .solarFlare: return .yellow
        case .solarEnergeticParticle: return .green
        case .interplanetaryShock: return .red
        case .radiationBeltEnhancement: return .blue
        case .highSpeedStream: return .cyan
        case .activeRegion: return .pink
        case .sunspot: return .brown
        }
    }
}

// Keep old FilterSheet for compatibility but unused
struct FilterSheet: View {
    @Bindable var viewModel: SpaceWeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        EventsFilterSheet(viewModel: viewModel)
    }
}

// MARK: - Supporting Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.orange)
            Text("Loading space weather data...")
                .font(Theme.mono(14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient)
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                retryAction()
            }
            .buttonStyle(.bordered)
        }
    }
}

struct EmptyStateView: View {
    let hasFilters: Bool
    let clearAction: () -> Void
    
    var body: some View {
        ContentUnavailableView {
            Label("No Events Found", systemImage: "sun.max.trianglebadge.exclamationmark")
        } description: {
            Text(hasFilters ? "Try adjusting your filters" : "No space weather events in the selected date range")
        } actions: {
            if hasFilters {
                Button("Clear Filters") {
                    clearAction()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
