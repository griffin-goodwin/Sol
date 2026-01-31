import Foundation
import SwiftUI

/// Main view model for space weather data
@MainActor
@Observable
class SpaceWeatherViewModel {
    // MARK: - Properties
    
    var events: [SpaceWeatherEvent] = []
    var isLoading = false
    var errorMessage: String?
    var selectedEventType: SpaceWeatherEventType?
    var searchText = ""
    
    // SDO Image properties
    var selectedWavelength: SDOWavelength = .aia171
    var sdoImageURL: URL?
    var isLoadingImage = false

    // Tab accent color driven by IMAGES tab selection
    var imageTabAccentColor: Color = .orange
    
    // Time range for data display (in hours) - matches SWPC API: 6, 24, 72, 168
    var overlayTimeRangeHours: Double = 24  // Default 1 day
    
    // Filter for event types shown in Activity/Events list
    var overlayEventTypes: Set<SpaceWeatherEventType> = [
        .solarFlare, .cme, .geomagneticStorm
    ]
    
    // X-ray flux time series data (raw and downsampled for chart)
    var xrayFluxData: [XRayFluxDataPoint] = []  // SXR-B (primary for classification)
    var xrayFluxDataA: [XRayFluxDataPoint] = [] // SXR-A (shorter wavelength)
    var isLoadingFlux = false
    private var lastFluxLoadTime: Date?
    private var cachedChartFluxData: [XRayFluxDataPoint] = []
    private var cachedChartFluxDataA: [XRayFluxDataPoint] = []
    private var lastChartFluxDataCount: Int = 0
    private var lastChartFluxDataACount: Int = 0
    
    // Flare probability forecast (next 24 hours)
    var flareProbabilityForecast: FlareProbabilityForecast = .unavailable
    var isLoadingProbabilities = false
    
    // Downsampled flux data for chart rendering - cached to avoid recomputation
    var chartFluxData: [XRayFluxDataPoint] {
        // Only recompute if data changed
        if xrayFluxData.count != lastChartFluxDataCount {
            lastChartFluxDataCount = xrayFluxData.count
            // Sample rate based on data size - aim for ~200 points max for smooth rendering
            let sampleRate = max(1, xrayFluxData.count / 200)
            cachedChartFluxData = stride(from: 0, to: xrayFluxData.count, by: sampleRate).compactMap { index in
                xrayFluxData.indices.contains(index) ? xrayFluxData[index] : nil
            }
        }
        return cachedChartFluxData
    }
    
    // Downsampled SXR-A flux data for chart rendering
    var chartFluxDataA: [XRayFluxDataPoint] {
        if xrayFluxDataA.count != lastChartFluxDataACount {
            lastChartFluxDataACount = xrayFluxDataA.count
            let sampleRate = max(1, xrayFluxDataA.count / 200)
            cachedChartFluxDataA = stride(from: 0, to: xrayFluxDataA.count, by: sampleRate).compactMap { index in
                xrayFluxDataA.indices.contains(index) ? xrayFluxDataA[index] : nil
            }
        }
        return cachedChartFluxDataA
    }
    
    private let helioviewerService = HelioviewerService()
    private let swpcService = SWPCService()
    
    // Track what time range we loaded
    private var lastFluxRangeHours: Double = 0
    
    // MARK: - Computed Properties
    
    var filteredEvents: [SpaceWeatherEvent] {
        var filtered = events
        
        // Filter by event type
        if let type = selectedEventType {
            filtered = filtered.filter { $0.type == type }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { event in
                event.title.localizedCaseInsensitiveContains(searchText) ||
                event.details.localizedCaseInsensitiveContains(searchText) ||
                event.type.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    var eventsByDate: [Date: [SpaceWeatherEvent]] {
        Dictionary(grouping: filteredEvents) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }
    
    var sortedDates: [Date] {
        eventsByDate.keys.sorted(by: >)
    }
    
    var eventTypeCounts: [SpaceWeatherEventType: Int] {
        var counts: [SpaceWeatherEventType: Int] = [:]
        for event in events {
            counts[event.type, default: 0] += 1
        }
        return counts
    }
    
    // MARK: - Event Actions
    
    func loadEvents(forceRefresh: Bool = false) async {
        // Skip if already loading (prevents race conditions)
        guard !isLoading || forceRefresh else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let hoursToFetch = Int(overlayTimeRangeHours)
            let endDate = Date() // Always fetch up to NOW to get recent events
            let startDate = endDate.addingTimeInterval(-Double(hoursToFetch) * 3600)
            
            // For longer time ranges, query in daily chunks to get better coverage
            var allEvents: [SpaceWeatherEvent] = []
            
            if hoursToFetch > 24 {
                // Query each day separately for better coverage
                let calendar = Calendar.current
                var currentEnd = endDate
                var daysQueried = 0
                let maxDays = hoursToFetch / 24
                
                while daysQueried < maxDays {
                    let currentStart = calendar.date(byAdding: .day, value: -1, to: currentEnd) ?? currentEnd.addingTimeInterval(-86400)

                    let dayEvents = try await helioviewerService.fetchUnifiedEvents(startDate: currentStart, endDate: currentEnd)
                    allEvents.append(contentsOf: dayEvents)
                    
                    currentEnd = currentStart
                    daysQueried += 1
                }
            } else {
                // Single query for short time ranges
                allEvents = try await helioviewerService.fetchUnifiedEvents(startDate: startDate, endDate: endDate)
            }
            
            // Fetch SWPC data (GOES flares + alerts)
            // GOES flares endpoint only has the last 7 days of data
            let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
            
            // Determine what portion of our time range overlaps with GOES data availability
            let goesDataStart = max(startDate, sevenDaysAgo)
            let hasGOESDataInRange = goesDataStart < endDate
            
            if hasGOESDataInRange {
                // Fetch GOES X-ray flares (accurate flare data with classes)
                do {
                    let goesFlares = try await swpcService.fetchUnifiedFlares()
                    // Filter flares to match our time range
                    let filteredFlares = goesFlares.filter { flare in
                        flare.date >= startDate && flare.date <= endDate
                    }
                    allEvents.append(contentsOf: filteredFlares)
                } catch {
                    // GOES flare fetch failed, continue with other data
                }
                
                // Fetch SWPC alerts (storms, radio blackouts, etc.)
                do {
                    let swpcAlerts = try await swpcService.fetchUnifiedAlerts(excludeFlares: true)
                    let filteredAlerts = swpcAlerts.filter { alert in
                        alert.date >= startDate && alert.date <= endDate
                    }
                    allEvents.append(contentsOf: filteredAlerts)
                } catch {
                    // SWPC alert fetch failed, continue with other data
                }
            }
            
            // Remove duplicates by ID and sort by date
            var seenIds = Set<String>()
            events = allEvents.filter { event in
                if seenIds.contains(event.id) { return false }
                seenIds.insert(event.id)
                return true
            }.sorted { $0.date > $1.date }
            
            isLoading = false
            
            // Process events for notifications
            NotificationManager.shared.processEventsForNotifications(events)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    /// Load SXR flux data for the current time range
    func loadXRayFlux() async {
        let hoursToFetch = Int(overlayTimeRangeHours)
        
        // Cache for 5 minutes unless range changed
        if let lastLoad = lastFluxLoadTime,
           Date().timeIntervalSince(lastLoad) < 300,
           lastFluxRangeHours == overlayTimeRangeHours,
           !xrayFluxData.isEmpty {
            return
        }
        
        isLoadingFlux = true
        if lastFluxRangeHours != overlayTimeRangeHours {
            xrayFluxData = []
            xrayFluxDataA = []
            lastChartFluxDataCount = 0
            lastChartFluxDataACount = 0
        }
        
        do {
            let (sxrA, sxrB) = try await swpcService.fetchXRayFluxBoth(hoursBack: hoursToFetch)
            xrayFluxData = sxrB
            xrayFluxDataA = sxrA
            lastFluxLoadTime = Date()
            lastFluxRangeHours = overlayTimeRangeHours
            lastChartFluxDataCount = 0
            lastChartFluxDataACount = 0
        } catch {
            // X-ray flux fetch failed
        }
        isLoadingFlux = false
    }
    
    func refresh() async {
        await loadEvents()
        await loadXRayFlux()
        await loadFlareProbabilities()
        await updateSDOImage()
    }
    
    /// Load SWPC flare probability forecast for next 24 hours
    func loadFlareProbabilities() async {
        guard !isLoadingProbabilities else { return }
        isLoadingProbabilities = true
        
        do {
            let newForecast = try await swpcService.fetchFlareProbabilities()
            if newForecast.hasData {
                flareProbabilityForecast = newForecast
            }
        } catch {
            // Flare probability fetch failed
        }
        
        isLoadingProbabilities = false
    }
    
    func clearFilters() {
        selectedEventType = nil
        searchText = ""
    }
    
    // MARK: - SDO Image Actions
    
    func updateSDOImage() async {
        isLoadingImage = true
        
        sdoImageURL = await helioviewerService.getSDOImageURL(
            date: Date(), // Always show current/latest image
            wavelength: selectedWavelength,
            width: 1024,
            height: 1024
        )
        
        isLoadingImage = false
    }
    
    func selectWavelength(_ wavelength: SDOWavelength) async {
        selectedWavelength = wavelength
        await updateSDOImage()
    }
    
    // MARK: - Event Detail Helpers
    
    /// Get SDO image URL for a specific event at a specific wavelength
    func getEventImageURL(for event: SpaceWeatherEvent, wavelength: SDOWavelength) async -> URL? {
        return await helioviewerService.getSDOImageURL(
            date: event.date,
            wavelength: wavelength,
            width: 1024,
            height: 1024
        )
    }
    
    /// Get LASCO image URL for CME events
    func getLASCOImageURL(for event: SpaceWeatherEvent, instrument: SolarInstrument) async -> URL? {
        return await helioviewerService.getLASCOImageURL(
            date: event.date,
            instrument: instrument,
            width: 1024,
            height: 1024
        )
    }
    
    /// Get WCS for an event's image with specific wavelength
    func getEventWCS(for event: SpaceWeatherEvent, wavelength: SDOWavelength) async -> SolarWCS? {
        return await helioviewerService.getImageWCS(date: event.date, wavelength: wavelength)
    }
}

// MARK: - Date Formatting Helpers

extension Date {
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }
    
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
