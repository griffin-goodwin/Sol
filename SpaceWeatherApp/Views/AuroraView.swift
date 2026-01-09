import SwiftUI
import MapKit

/// Interactive 3D globe showing real-time aurora forecast
struct AuroraView: View {
    @State private var auroraPoints: [AuroraPoint] = []
    @State private var currentKp: KpIndexPoint?
    @State private var kpForecast: [KpIndexPoint] = []
    @State private var selectedHemisphere: Hemisphere = .north
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    @State private var showInfo = false
    @State private var showKpDetails = false
    @State private var maxPointsPerHemisphere: Int = 20000
    
    private let auroraService = AuroraService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Aurora-themed background
                AuroraBackground()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Current conditions card
                        currentConditionsCard
                        
                        // Interactive globe
                        globeSection
                        
                        // Hemisphere selector
                        hemisphereSelector
                        
                        // Aurora visibility info
                        visibilityInfoCard
                        
                        // Legend
                        legendCard
                        
                        // Last updated
                        if let lastUpdated {
                            Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.bottom, Theme.Spacing.lg)
                        }
                    }
                    .padding(.vertical)
                }

                // Lightweight compass overlay (bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        AuroraCompassOverlay(auroraPoints: filteredPoints, selectedHemisphere: selectedHemisphere)
                            .padding()
                    }
                }

                if isLoading {
                    loadingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AURORA")
                        .font(Theme.mono(42, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(Theme.auroraTitleGradient)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .sheet(isPresented: $showInfo) {
                AuroraInfoSheet()
            }
            .sheet(isPresented: $showKpDetails) {
                KPForecastSheet(forecast: kpForecast)
            }
            // Fetch full global dataset once; hemisphere changes do not re-fetch
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .onChange(of: selectedHemisphere) { oldValue, newValue in
                let northCount = auroraPoints.filter { $0.latitude > 0 }.count
                let southCount = auroraPoints.filter { $0.latitude < 0}.count
                let usedCount = filteredPoints.count
                
            }
        }
    }
    
    // MARK: - Current Conditions Card
    
    private var currentConditionsCard: some View {
        HStack(spacing: Theme.Spacing.xl) {
            // Kp Index
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Kp INDEX")
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                
                if let kp = currentKp {
                    Text(String(format: "%.1f", kp.kpIndex))
                        .font(Theme.mono(42, weight: .bold))
                        .foregroundStyle(kpColor(for: kp.kpIndex))
                    
                    Text(kp.level.rawValue)
                        .font(Theme.mono(12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("--")
                        .font(Theme.mono(42, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            
            Spacer()
            
            // KP forecast (small bar chart)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("KP FORECAST")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                    
                    Button {
                        showKpDetails = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                
                if kpForecast.isEmpty {
                    Text("Loading…")
                        .font(Theme.mono(14, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    // Use the 12 samples starting at the first forecast time >= now
                    // Show the next N forecast bars (limited to 12) with proper baseline
                    let now = Date()
                    let startIndex = kpForecast.firstIndex(where: { ($0.date ?? Date.distantPast) >= now }) ?? max(0, kpForecast.count - 12)
                    let endIndex = min(kpForecast.count, startIndex + 12)
                    let samples = Array(kpForecast[startIndex..<endIndex])
                    let chartHeight: CGFloat = 80
                    let maxDisplayKp: Double = 9.0
                    let barWidth: CGFloat = 10
                    let barSpacing: CGFloat = 4
                    let totalChartWidth = CGFloat(samples.count) * barWidth + CGFloat(samples.count - 1) * barSpacing

                    VStack(alignment: .leading, spacing: 0) {
                        // Chart area
                        HStack(alignment: .bottom, spacing: 0) {
                            // Y-axis labels
                            VStack(spacing: 0) {
                                ForEach([9, 6, 3, 0], id: \.self) { value in
                                    Text("\(value)")
                                        .font(Theme.mono(9))
                                        .foregroundStyle(Theme.tertiaryText)
                                        .frame(maxHeight: .infinity, alignment: value == 9 ? .top : (value == 0 ? .bottom : .center))
                                }
                            }
                            .frame(width: 12, height: chartHeight)
                            
                            // Chart area - bars flush against y-axis
                            ZStack(alignment: .bottomLeading) {
                                // Baseline
                                Rectangle()
                                    .fill(Theme.tertiaryText.opacity(0.3))
                                    .frame(width: totalChartWidth, height: 1)
                                
                                // Bars - starting at x=0
                                HStack(alignment: .bottom, spacing: barSpacing) {
                                    ForEach(Array(samples.enumerated()), id: \.offset) { idx, entry in
                                        VStack(spacing: 0) {
                                            Spacer(minLength: 0)
                                            
                                            let barHeight = (entry.kpIndex / maxDisplayKp) * chartHeight
                                            Rectangle()
                                                .fill(kpColor(for: entry.kpIndex))
                                                .frame(width: barWidth, height: max(2, barHeight))
                                                .cornerRadius(2, antialiased: true)
                                        }
                                        .frame(width: barWidth, height: chartHeight)
                                    }
                                }
                            }
                            .frame(width: totalChartWidth, height: chartHeight)



                        }
                        
                        // X-axis labels removed (time text not required)
                        
                    }
                    .onAppear {
                        // Debug: print computed bar heights and sample indices used for plotting
                        let nowForDebug = Date()
                        for (sIdx, sEntry) in samples.enumerated() {
                            let globalIdx = kpForecast.firstIndex(where: { $0.timeTag == sEntry.timeTag && $0.kpIndex == sEntry.kpIndex }) ?? sIdx
                            let barHeight = (sEntry.kpIndex / maxDisplayKp) * chartHeight
                            let predictedFlag: Bool
                            if let _ = sEntry.date {
                                let forecastDates = kpForecast.compactMap { $0.date }
                                let boundary = forecastDates.firstIndex(where: { $0 >= nowForDebug }) ?? forecastDates.count
                                predictedFlag = globalIdx >= boundary
                            } else {
                                predictedFlag = false
                            }
                            print(String(format: "🔎 Bar debug: sample=%d global=%d kp=%.2f height=%.2f predicted=%@", sIdx, globalIdx, sEntry.kpIndex, barHeight, predictedFlag ? "YES" : "NO"))
                        }
                    }

                }
                // Summary: max kp in forecast and any NOAA scale
                let maxKp = Int((kpForecast.map { $0.kpIndex }.max() ?? 0).rounded())
                let scale = kpForecast.compactMap { $0.estimated }.first
                HStack {
                    Text("Max: \(maxKp)")
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundStyle(kpColor(for: Double(maxKp)))
                    if let scale {
                        Text(scale)
                            .font(Theme.mono(11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.leading, 6)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .padding(.horizontal)
    }
    
    // MARK: - Globe Section
    
    private var globeSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                // MapKit Globe view – pass full dataset and a target max per hemisphere
                AuroraMapGlobeView(
                    auroraPoints: auroraPoints,
                    hemisphere: selectedHemisphere,
                    maxCircles: maxPointsPerHemisphere
                )
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                // Overlay hint
                VStack {
                    HStack {
                        Spacer()
                        HStack {
                            Label("Drag to explore", systemImage: "hand.draw")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(Theme.Spacing.md)

                    Spacer()
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Hemisphere Selector
    
    private var hemisphereSelector: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(Hemisphere.allCases) { hemisphere in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedHemisphere = hemisphere
                    }
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: hemisphere == .north ? "globe.americas" : "globe.asia.australia")
                            .font(.system(size: 24))
                        Text(hemisphere.rawValue)
                            .font(Theme.mono(12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(selectedHemisphere == hemisphere ? Theme.auroraGreen.opacity(0.2) : Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(selectedHemisphere == hemisphere ? Theme.auroraGreen : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedHemisphere == hemisphere ? Theme.auroraGreen : Theme.secondaryText)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Visibility Info Card
    
    private var visibilityInfoCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "eye")
                    .foregroundStyle(Theme.auroraGreen)
                Text("VISIBILITY FORECAST")
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            
            if let kp = currentKp {
                Text(kp.level.visibilityDescription)
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.primaryText)
                
                HStack {
                    Text("Visible down to latitude:")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    // Prefer a data-driven visibility estimate from the rendered points (50% threshold).
                    if let visLat = visibilityLatitudeUsingPoints(for: selectedHemisphere, threshold: 50.0) {
                        Text("~\(visLat)° \(selectedHemisphere == .north ? "N" : "S")")
                            .font(Theme.mono(14, weight: .semibold))
                            .foregroundStyle(Theme.auroraGreen)
                    } else {
                        // Fallback to Kp-derived estimate when no points meet threshold
                        Text("~\(Int(kp.level.visibilityLatitude))° \(selectedHemisphere == .north ? "N" : "S")")
                            .font(Theme.mono(14, weight: .semibold))
                            .foregroundStyle(Theme.auroraGreen)
                    }
                }
            } else {
                Text("Loading visibility data...")
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .padding(.horizontal)
    }
    
    // MARK: - Legend Card
    
    private var legendCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("PROBABILITY LEGEND")
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
            
            // 10-point bins (0-10, 10-20, ..., 90-100)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.lg) {
                    ForEach(0..<10) { i in
                        let low = i * 10
                        let high = i == 9 ? 100 : (low + 10)
                        let label = i == 0 ? "0-10%" : "\(low)-\(high)%"
                        legendItem(color: auroraColor(for: Double(low + (high - low)/2)), label: label, opacity: 1.0)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
            .frame(height: 72)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .padding(.horizontal)
    }
    
    private func legendItem(color: Color, label: String, opacity: Double) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color.opacity(opacity))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            Text(label)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    // Legend color now uses shared `auroraColor(for:)` helper in Utilities/AuroraColors.swift
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.auroraGreen)
                
                Text("Loading aurora data...")
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(Theme.Spacing.xxl)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredPoints: [AuroraPoint] {
        // Filter the global dataset by hemisphere (AuroraMapGlobeView will handle sampling/capping)
        let result: [AuroraPoint]
        switch selectedHemisphere {
        case .north:
            result = auroraPoints.filter { $0.latitude > 0 }
        case .south:
            result = auroraPoints.filter { $0.latitude < 0 }
        }
        print("🔎 Filtered points for \(selectedHemisphere.rawValue): \(result.count) of total \(auroraPoints.count)")
        return result
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let pointsTask = auroraService.fetchAuroraPoints()
            async let kpTask = auroraService.fetchCurrentKp()
            async let forecastTask = auroraService.fetchKpForecast()

            let (points, kp, forecast) = try await (pointsTask, kpTask, forecastTask)

            await MainActor.run {
                self.auroraPoints = points
                self.currentKp = kp
                self.kpForecast = forecast
                self.lastUpdated = Date()
                self.isLoading = false

                let northCount = points.filter { $0.latitude > 0 }.count
                let southCount = points.filter { $0.latitude < 0 }.count
                print("✅ Loaded aurora data: total=\(points.count), north=\(northCount), south=\(southCount)")
                if let kp = kp {
                    print("✅ Current Kp: \(kp.kpIndex) (\(kp.level.rawValue))")
                }
                print("✅ Loaded KP forecast: \(forecast.count) entries")

                // Debug: show current UTC and forecast boundary (first date >= now)
                let now = Date()
                let iso = ISO8601DateFormatter()
                let forecastDates = forecast.compactMap { $0.date }
                let boundary = forecastDates.firstIndex(where: { $0 >= now }) ?? forecastDates.count
                print("🔎 KP debug: now=\(iso.string(from: now)), boundaryIndex=\(boundary) (first date >= now)")
                if !forecastDates.isEmpty {
                    print("🔎 KP dates (first \(min(12, forecastDates.count))):")
                    for (i, d) in forecastDates.prefix(12).enumerated() {
                        print("  \(i): \(iso.string(from: d))")
                    }
                    // Print entries around the boundary for context
                    let start = max(0, boundary - 3)
                    let end = min(forecast.count - 1, boundary + 3)
                    print("🔎 KP context around boundary (indices \(start)..\(end)):")
                    for i in start...end {
                        let p = forecast[i]
                        let dateStr = p.date.map { iso.string(from: $0) } ?? "-"
                        let est = p.estimated ?? "-"
                        print(String(format: "  %2d: time=%@ kp=%.1f est=%@ date=%@", i, p.timeTag, p.kpIndex, est, dateStr))
                    }
                }

                // Debug: print all KP entries plotted
                print("🔎 KP all plotted entries (count=\(forecast.count)):")
                for (i, p) in forecast.enumerated() {
                    let dateStr = p.date.map { iso.string(from: $0) } ?? "-"
                    let est = p.estimated ?? "-"
                    print(String(format: "  %2d: time=%@ kp=%.1f est=%@ date=%@", i, p.timeTag, p.kpIndex, est, dateStr))
                }

                // Debug: highlight any entries with kp == 0.0
                let zeroIndices = forecast.enumerated().filter { abs($0.element.kpIndex) < 1e-6 }.map { $0.offset }
                if !zeroIndices.isEmpty {
                    print("⚠️ KP zeros at indices: \(zeroIndices)")
                } else {
                    print("✅ No KP==0.0 entries found in forecast")
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            print("❌ Aurora: Failed to load data - \(error)")
        }
    }
    
    // MARK: - Helpers
    
    
    
    private func auroraStatusText(for probability: Double) -> String {
        switch probability {
        case 0..<10: return "Quiet"
        case 10..<30: return "Minor Activity"
        case 30..<50: return "Moderate Activity"
        case 50..<70: return "High Activity"
        case 70...: return "Storm Conditions"
        default: return "Unknown"
        }
    }
    
    private func auroraStatusColor(for probability: Double) -> Color {
        switch probability {
        case 0..<10: return Theme.tertiaryText
        case 10..<30: return Theme.auroraLow
        case 30..<50: return Theme.auroraModerate
        case 50..<70: return Theme.auroraHigh
        case 70...: return Theme.auroraExtreme
        default: return Theme.tertiaryText
        }
    }

    /// Compute x-axis label for a forecast entry.
    /// Labels are relative to current UTC time (e.g. "Now", "+1h") and
    /// will be marked as "P" (predicted) or "E" (estimated) based on the
    /// closest forecast time: entries after the closest time are predictions.
    private func xLabel(for entry: KpIndexPoint, samples: [KpIndexPoint], index: Int) -> String {
        let now = Date()

        // Parse dates for samples (preserve ordering)
        let dates = samples.compactMap { $0.date }
        guard let entryDate = entry.date, !dates.isEmpty else { return "" }

        // Find the first sample whose date is >= now — entries at or after this are predictions
        let boundaryIndex = dates.firstIndex(where: { $0 >= now }) ?? dates.count
        let isPredicted = index >= boundaryIndex

        let interval = Int(round(entryDate.timeIntervalSince(now) / 3600.0)) // hours
        let timePart: String
        if abs(interval) <= 0 { timePart = "Now" }
        else if interval > 0 { timePart = "+\(interval)h" }
        else { timePart = "\(interval)h" }

        let suffix = isPredicted ? " P" : " E"
        return "\(timePart)\(suffix)"
    }

    private func shortHourLabel(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(abbreviation: "UTC")
        df.dateFormat = "MMM d H'h'" // e.g. "Jan 8 14h"
        return df.string(from: date)
    }

    /// Compute the equatorward visibility latitude for a hemisphere where probability >= `threshold`.
    /// Returns an integer degree (positive) representing degrees from the equator (e.g. 55 means 55°N or 55°S).
    private func visibilityLatitudeUsingPoints(for hemisphere: Hemisphere, threshold: Double) -> Int? {
        // Filter to hemisphere points
        let points = auroraPoints.filter { hemisphere == .north ? $0.latitude > 0 : $0.latitude < 0 }
        // Keep only points that meet or exceed threshold
        let qualifying = points.filter { $0.probability >= threshold }
        guard !qualifying.isEmpty else { return nil }

        if hemisphere == .north {
            // Equatorward visibility = smallest positive latitude among qualifying points
            let minLat = qualifying.map { $0.latitude }.min() ?? 90.0
            return Int(round(minLat))
        } else {
            // Southern hemisphere latitudes are negative; choose the largest (closest to zero)
            let maxLat = qualifying.map { $0.latitude }.max() ?? -90.0
            return Int(round(abs(maxLat)))
        }
    }
}

// MARK: - Aurora Info Sheet

struct AuroraInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    infoSection(
                        title: "What is the Aurora?",
                        content: "The aurora (Northern/Southern Lights) occurs when charged particles from the Sun collide with gases in Earth's atmosphere, creating beautiful displays of light."
                    )
                    
                    infoSection(
                        title: "Kp Index",
                        content: "The Kp index measures geomagnetic activity on a scale of 0-9. Higher values mean stronger geomagnetic storms and aurora visible at lower latitudes."
                    )
                    
                    infoSection(
                        title: "Reading the Globe",
                        content: "The colored regions show aurora probability. Brighter green areas have higher chances of visible aurora. The oval shape around the poles is the typical auroral zone."
                    )
                    
                    infoSection(
                        title: "Best Viewing Conditions",
                        content: "• Dark skies (no city lights)\n• Clear weather\n• Kp index ≥ 4 for mid-latitudes\n• Look north (or south in Southern Hemisphere)\n• Best times: midnight to 3 AM local time"
                    )
                    
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Data Source")
                            .font(Theme.mono(14, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                        
                        Text("NOAA Space Weather Prediction Center\nOVATION Aurora Forecast Model")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("About Aurora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func infoSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.mono(14, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            
            Text(content)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(4)
        }
    }
}

// MARK: - KP Forecast Sheet

struct KPForecastSheet: View {
    let forecast: [KpIndexPoint]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header explanation
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("3-Day Geomagnetic Activity Forecast (UTC)")
                            .font(Theme.mono(12, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        
                        HStack(spacing: Theme.Spacing.md) {
                            Label("E", systemImage: "circle.fill")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.auroraModerate)
                            Text("Estimated (observed)")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.tertiaryText)
                            
                            Label("P", systemImage: "circle.fill")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.auroraGreen)
                            Text("Predicted")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, Theme.Spacing.sm)
                    
                    if forecast.isEmpty {
                        Text("No forecast data available")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Theme.Spacing.xxl)
                    } else {
                        let now = Date()
                        let dates = forecast.compactMap { $0.date }
                        let boundary = dates.firstIndex(where: { $0 >= now }) ?? dates.count

                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(forecast.enumerated()), id: \.offset) { idx, entry in
                                forecastRow(entry: entry, index: idx, boundary: boundary)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, Theme.Spacing.lg)
            }
            .background(AuroraBackground())
            .navigationTitle("KP Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { 
                        dismiss() 
                    }
                    .foregroundStyle(Theme.auroraGreen)
                }
            }
        }
    }
    
    private func forecastRow(entry: KpIndexPoint, index: Int, boundary: Int) -> some View {
        let isPredicted = index >= boundary
        // Precompute time text outside the ViewBuilder to avoid placing statements inside the view body
        let timeText: String? = {
            guard let date = entry.date else { return nil }
            let now = Date()
            let label = shortHourLabel(from: date)
            if abs(date.timeIntervalSince(now)) < 3600 { // within an hour -> Now
                return "Now"
            }  else {
                return label
            }
        }()

        return HStack(spacing: Theme.Spacing.md) {
            // Time and date
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.timeTag)
                        .font(Theme.mono(13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    
                    // P/E indicator
                    Text(isPredicted ? "P" : "E")
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isPredicted ? Theme.auroraGreen : Theme.auroraModerate)
                        .clipShape(Capsule())
                }
                
                if let timeText = timeText {
                    Text(timeText)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            
            Spacer()
            
            // Kp value and visual bar
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(String(format: "%.1f", entry.kpIndex))
                        .font(Theme.mono(20, weight: .bold))
                        .foregroundStyle(kpColor(for: entry.kpIndex))
                    
                    Text("Kp")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                
                // Mini bar indicator
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.tertiaryText.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        Rectangle()
                            .fill(kpColor(for: entry.kpIndex))
                            .frame(width: geo.size.width * CGFloat(entry.kpIndex / 9.0), height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
                .frame(maxWidth: 80)
                
                if let scale = entry.estimated {
                    Text(scale)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(
                    isPredicted ? Theme.auroraGreen.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private func shortHourLabel(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(abbreviation: "UTC")
        df.dateFormat = "MMM d H'h'" // e.g. "Jan 8 14h"
        return df.string(from: date)
    }
}

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            // Base dark background
            Color(red: 0.02, green: 0.04, blue: 0.08)
                .ignoresSafeArea()
            
            // Aurora glow effect
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Theme.auroraGreen.opacity(0.15), location: 0.0),
                    .init(color: Theme.auroraGreen.opacity(0.05), location: 0.3),
                    .init(color: Color.clear, location: 0.6)
                ]),
                center: .top,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            
            // Secondary glow
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.2, green: 0.8, blue: 0.6).opacity(0.1), location: 0.0),
                    .init(color: Color.clear, location: 0.5)
                ]),
                center: .topTrailing,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    AuroraView()
        .preferredColorScheme(.dark)
}

// MARK: - Helpers

fileprivate func kpColor(for kp: Double) -> Color {
    switch kp {
    case 0..<4: return Theme.auroraLow
    case 4..<5: return Theme.auroraModerate
    case 5..<6: return Theme.auroraHigh
    case 6..<7: return .orange
    case 7...: return Theme.auroraExtreme
    default: return Theme.tertiaryText
    }
}

