import SwiftUI

/// Combined Activity view showing conditions summary and event list
struct ActivityView: View {
    @Bindable var viewModel: SpaceWeatherViewModel
    @State private var showingFilters = false
    @State private var expandedSummary = true
    @State private var showFluxChart = true
    
    // Filter events by selected types
    private var filteredEvents: [SpaceWeatherEvent] {
        return viewModel.events.filter { event in
            viewModel.overlayEventTypes.contains(event.type)
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                MeshGradientBackground(style: .activity)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Collapsible summary section
                        summarySection
                            .scaleFade(delay: 0.1)

                        // X-Ray Flux Chart
                        if showFluxChart {
                            XRayFluxChart(viewModel: viewModel, height: 100)
                                .scaleFade(delay: 0.2)
                        }

                        // Quick stats row
                        quickStatsRow
                            .slideIn(from: .leading, delay: 0.25)

                        // Events list
                        eventsSection
                            .scaleFade(delay: 0.3)
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ACTIVITY")
                        .font(.system(size: 32, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(Theme.activityTitleGradient)
                        .shadow(color: Theme.accentSecondary.opacity(0.4), radius: 8, x: 0, y: 0)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation { showFluxChart.toggle() }
                    } label: {
                        Image(systemName: showFluxChart ? "chart.xyaxis.line" : "chart.line.downtrend.xyaxis")
                    }
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
            .task {
                // Load probability forecast when view appears (if not already loaded)
                if !viewModel.flareProbabilityForecast.hasData {
                    await viewModel.loadFlareProbabilities()
                }
            }
            .onChange(of: viewModel.overlayTimeRangeHours) { _, _ in
                // Reload flux and events when time range changes
                Task {
                    await viewModel.loadXRayFlux()
                    await viewModel.loadEvents()
                    await viewModel.loadFlareProbabilities()
                }
            }
        }
    }
    
    // MARK: - Summary Section
    
    private var summarySection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Header with condition
            HStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("SPACE WEATHER ACTIVITY")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .tracking(1.5)
                    Text(overallConditionText)
                        .font(Theme.mono(24, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Condition indicator with glow
                ZStack {
                    Circle()
                        .fill(overallConditionColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                        .breathingScale(min: 0.95, max: 1.05, duration: 2)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [overallConditionColor, overallConditionColor.opacity(0.7)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 18
                            )
                        )
                        .frame(width: 36, height: 36)
                        .pulsingGlow(color: overallConditionColor, radius: 10)
                    Image(systemName: overallConditionIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            
            // Divider with subtle gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.05), .white.opacity(0.15), .white.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            // Key metrics - Flare Probabilities (next 24h)
            HStack(spacing: 0) {
                MetricItem(
                    value: viewModel.flareProbabilityForecast.hasData ? "\(viewModel.flareProbabilityForecast.mClassProbability)%" : "—",
                    label: "M-Class (1d)",
                    color: mClassProbabilityColor
                )
                
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 40)
                
                MetricItem(
                    value: viewModel.flareProbabilityForecast.hasData ? "\(viewModel.flareProbabilityForecast.xClassProbability)%" : "—",
                    label: "X-Class (1d)",
                    color: xClassProbabilityColor
                )
                
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 40)
                
                MetricItem(
                    value: peakFlareClass,
                    label: "Peak Flare (\(formatTimeRange(viewModel.overlayTimeRangeHours)))",
                    color: peakFlareColor
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(overallConditionColor.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Quick Stats Row
    
    private var quickStatsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Time window selector
            Menu {
                ForEach([6.0, 24.0, 72.0, 168.0], id: \.self) { hours in
                    Button {
                        withAnimation(Theme.Animation.standard) {
                            viewModel.overlayTimeRangeHours = hours
                        }
                    } label: {
                        HStack {
                            Text(formatTimeRange(hours))
                            if viewModel.overlayTimeRangeHours == hours {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                    Text(formatTimeRange(viewModel.overlayTimeRangeHours))
                        .font(Theme.mono(13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            
            Spacer()
            
            // Event count pill
            HStack(spacing: Theme.Spacing.xs) {
                Text("\(filteredEvents.count)")
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(.white)
                Text("events")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondaryText)
            }
            
            // Flare class breakdown (only flares have severity labels)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach([
                    (sev: SpaceWeatherEvent.EventSeverity.extreme, label: "X"),
                    (sev: .high, label: "M"),
                    (sev: .moderate, label: "C"),
                    (sev: .weak, label: "<C")
                ], id: \.label) { item in
                    let count = filteredEvents.filter { $0.severity == item.sev }.count
                    if count > 0 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(colorForSeverity(item.sev))
                                .frame(width: 6, height: 6)
                            Text("\(count)\(item.label)")
                                .font(Theme.mono(10, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Events Section
    
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("EVENTS")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .tracking(1.5)
                
                Spacer()
                
                if !filteredEvents.isEmpty {
                    Text("\(filteredEvents.count)")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            if viewModel.isLoading && filteredEvents.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: Theme.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Theme.accentColor)
                        Text("Loading events...")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Spacer()
                }
                .padding(.vertical, 48)
            } else if filteredEvents.isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentColor.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: "sun.max")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.accentColor.opacity(0.5))
                    }
                    Text("No events in time window")
                        .font(Theme.mono(14, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Button {
                        withAnimation(Theme.Animation.standard) {
                            viewModel.overlayTimeRangeHours = min(viewModel.overlayTimeRangeHours * 2, 168)
                        }
                    } label: {
                        Text("Expand Time Range")
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .pressable()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                        NavigationLink(destination: EventDetailView(event: event, viewModel: viewModel)) {
                            ActivityEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .staggeredAppearance(index: index, baseDelay: 0.1)

                        if index < filteredEvents.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Strongest flare severity in the filtered time window
    private var strongestFlareSeverity: SpaceWeatherEvent.EventSeverity {
        let flares = filteredEvents.filter { $0.type == .solarFlare }
        return flares.max(by: { compareFlareStrength($0, $1) })?.severity ?? .none
    }
    
    private var overallConditionText: String {
        switch strongestFlareSeverity {
        case .extreme: return "Extreme"
        case .high: return "High"
        case .moderate: return "Moderate"
        case .weak: return "Weak"
        case .none: return "Quiet"
        }
    }
    
    private var overallConditionColor: Color {
        switch strongestFlareSeverity {
        case .extreme: return .red
        case .high: return .orange
        case .moderate: return .yellow
        case .weak: return .green
        case .none: return .green
        }
    }
    
    private var overallConditionIcon: String {
        switch strongestFlareSeverity {
        case .extreme: return "bolt.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .moderate: return "sun.max.fill"
        case .weak: return "sun.min.fill"
        case .none: return "checkmark"
        }
    }
    
    private var activeRegionCount: Int {
        viewModel.events.filter { $0.type == .activeRegion || $0.type == .sunspot }.count
    }
    
    private var highSeverityCount: Int {
        viewModel.events.filter { $0.severity == .high || $0.severity == .extreme }.count
    }
    
    private var mClassProbabilityColor: Color {
        let prob = viewModel.flareProbabilityForecast.mClassProbability
        if prob >= 60 { return .orange }
        if prob >= 30 { return .yellow }
        return .green
    }
    
    private var xClassProbabilityColor: Color {
        let prob = viewModel.flareProbabilityForecast.xClassProbability
        if prob >= 30 { return .red }
        if prob >= 15 { return .orange }
        if prob >= 5 { return .yellow }
        return .green
    }
    
    private var peakFlareClass: String {
        // Use filtered events (respects time range filter)
        let flares = filteredEvents.filter { $0.type == .solarFlare }
        if let strongest = flares.max(by: { compareFlareStrength($0, $1) }) {
            // Title format is "Flare: M1.5" or "Solar Flare: X2.0"
            if let colonIndex = strongest.title.firstIndex(of: ":") {
                let afterColon = strongest.title[strongest.title.index(after: colonIndex)...]
                return afterColon.trimmingCharacters(in: .whitespaces)
            }
            // Fallback: try to extract class letter + number
            let pattern = #"([ABCMX]\d+\.?\d*)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: strongest.title, range: NSRange(strongest.title.startIndex..., in: strongest.title)),
               let range = Range(match.range(at: 1), in: strongest.title) {
                return String(strongest.title[range])
            }
            return strongest.severity.rawValue
        }
        return "—"
    }
    
    private var peakFlareColor: Color {
        // Use filtered events (respects time range filter)
        let flares = filteredEvents.filter { $0.type == .solarFlare }
        if let strongest = flares.max(by: { compareFlareStrength($0, $1) }) {
            switch strongest.severity {
            case .extreme: return .red
            case .high: return .orange
            case .moderate: return .yellow
            case .weak: return .green
            case .none: return .gray
            }
        }
        return .gray
    }
    
    private func compareFlareSeverity(_ a: SpaceWeatherEvent, _ b: SpaceWeatherEvent) -> Bool {
        let severityOrder: [SpaceWeatherEvent.EventSeverity] = [.none, .weak, .moderate, .high, .extreme]
        let aIndex = severityOrder.firstIndex(of: a.severity) ?? 0
        let bIndex = severityOrder.firstIndex(of: b.severity) ?? 0
        return aIndex < bIndex
    }
    
    /// Compare flare strength including the numeric magnitude (e.g., M5.2 > M1.5)
    private func compareFlareStrength(_ a: SpaceWeatherEvent, _ b: SpaceWeatherEvent) -> Bool {
        let aStrength = parseFlareStrength(a.title)
        let bStrength = parseFlareStrength(b.title)
        return aStrength < bStrength
    }
    
    /// Parse flare class into a comparable numeric value
    /// X1.0 = 1.0, M1.0 = 0.1, C1.0 = 0.01, B1.0 = 0.001, A1.0 = 0.0001
    private func parseFlareStrength(_ title: String) -> Double {
        let pattern = #"([ABCMX])(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let classRange = Range(match.range(at: 1), in: title),
              let numRange = Range(match.range(at: 2), in: title) else {
            return 0
        }
        
        let classLetter = String(title[classRange]).uppercased()
        let magnitude = Double(title[numRange]) ?? 1.0
        
        // Convert to a single scale where X1 = 1.0
        let classMultiplier: Double
        switch classLetter {
        case "X": classMultiplier = 1.0
        case "M": classMultiplier = 0.1
        case "C": classMultiplier = 0.01
        case "B": classMultiplier = 0.001
        case "A": classMultiplier = 0.0001
        default: classMultiplier = 0
        }
        
        return classMultiplier * magnitude
    }
    
    private func formatTimeRange(_ hours: Double) -> String {
        if hours < 24 { return "\(Int(hours))h" }
        else if hours == 24 { return "1d" }
        else { return "\(Int(hours / 24))d" }
    }
    
    private func colorForSeverity(_ severity: SpaceWeatherEvent.EventSeverity) -> Color {
        switch severity {
        case .weak: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .extreme: return .red
        case .none: return .gray
        }
    }
}

// MARK: - Metric Item

struct MetricItem: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.mono(20, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.3), radius: 4)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
            Text(label)
                .font(Theme.mono(9, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Activity Event Row

struct ActivityEventRow: View {
    let event: SpaceWeatherEvent
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Event icon with colored background
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(colorForType(event.type).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: event.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorForType(event.type))
            }
            
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(event.title)
                        .font(Theme.mono(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    // Show strength if available (for flares without class)
                    if event.type == .solarFlare, let strength = event.strengthDisplay {
                        if !event.title.contains(strength) {
                            Text(strength)
                                .font(Theme.mono(10, weight: .semibold))
                                .foregroundStyle(Theme.accentColor)
                        }
                    }
                }
                
                HStack(spacing: Theme.Spacing.sm) {
                    // Source badge
                    SourceBadge(source: event.source)
                    
                    Text(event.type.displayName)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                    
                    if event.hpcX != nil {
                        Circle()
                            .fill(Theme.quaternaryText)
                            .frame(width: 3, height: 3)
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.quaternaryText)
                    }
                }
            }
            
            Spacer(minLength: Theme.Spacing.sm)
            
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                SeverityBadge(severity: event.severity)
                Text(event.date.relativeTime)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(Rectangle())
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
        case "pink": return .pink
        default: return .gray
        }
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
    let source: SpaceWeatherEvent.EventSource
    
    var body: some View {
        Text(source.displayName)
            .font(Theme.mono(8, weight: .bold))
            .foregroundStyle(colorForSource)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(colorForSource.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    
    private var colorForSource: Color {
        switch source {
        case .hek: return .cyan
        case .goes: return Theme.accentColor
        case .swpc: return Theme.danger
        case .donki: return .purple
        }
    }
}

// MARK: - Source Badge Large (for detail view)

struct SourceBadgeLarge: View {
    let source: SpaceWeatherEvent.EventSource
    
    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(colorForSource)
                .frame(width: 8, height: 8)
                .shadow(color: colorForSource.opacity(0.5), radius: 3)
            Text(source.displayName)
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(colorForSource)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(colorForSource.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(colorForSource.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var colorForSource: Color {
        switch source {
        case .hek: return .blue
        case .goes: return .orange
        case .swpc: return .red
        case .donki: return .purple
        }
    }
}

#Preview {
    ActivityView(viewModel: SpaceWeatherViewModel())
}
