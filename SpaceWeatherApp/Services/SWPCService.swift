import Foundation

/// Service for fetching NOAA Space Weather Prediction Center (SWPC) data
/// Includes GOES X-ray flares, alerts, and real-time flux data
actor SWPCService {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // API Endpoints
    private let xrayFlaresURL = "https://services.swpc.noaa.gov/json/goes/primary/xray-flares-7-day.json"
    private let alertsURL = "https://services.swpc.noaa.gov/products/alerts.json"
    private let xrayFlux1DayURL = "https://services.swpc.noaa.gov/json/goes/primary/xrays-1-day.json"
    private let xrayFlux3DayURL = "https://services.swpc.noaa.gov/json/goes/primary/xrays-3-day.json"
    private let xrayFlux7DayURL = "https://services.swpc.noaa.gov/json/goes/primary/xrays-7-day.json"
    private let xrayFlux6HourURL = "https://services.swpc.noaa.gov/json/goes/primary/xrays-6-hour.json"
    private let solarProbabilitiesURL = "https://services.swpc.noaa.gov/json/solar_probabilities.json"
    
    // SXR B wavelength band (1-8 Angstroms) - used for flare classification
    private let sxrBEnergyBand = "0.1-0.8nm"
    // SXR A wavelength band (0.5-4 Angstroms) - shorter wavelength, more energetic
    private let sxrAEnergyBand = "0.05-0.4nm"
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - GOES X-Ray Flares
    
    /// Fetch the latest X-ray flares from GOES satellite
    func fetchXRayFlares() async throws -> [GOESXRayFlare] {
        guard let url = URL(string: xrayFlaresURL) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        let flares = try decoder.decode([GOESXRayFlare].self, from: data)
        
        return flares
    }
    
    /// Convert GOES X-ray flares to unified SpaceWeatherEvent format
    func fetchUnifiedFlares() async throws -> [SpaceWeatherEvent] {
        let flares = try await fetchXRayFlares()
        return flares.compactMap { flare -> SpaceWeatherEvent? in
            guard let peakTime = parseDate(flare.maxTime) else { return nil }
            
            let severity = determineFlareSeverity(flareClass: flare.maxClass ?? "C1.0")
            let title = buildFlareTitle(flare: flare)
            let details = buildFlareDetails(flare: flare)
            
            return SpaceWeatherEvent(
                id: "goes-\(flare.timeTag ?? UUID().uuidString)",
                type: .solarFlare,
                date: peakTime,
                title: title,
                details: details,
                severity: severity,
                link: nil,
                source: .goes,
                peakIntensity: flare.maxXrlong
            )
        }
    }
    
    private func buildFlareTitle(flare: GOESXRayFlare) -> String {
        if let flareClass = flare.maxClass, !flareClass.isEmpty {
            return "Flare: \(flareClass)"
        }
        // Fallback to intensity if no class
        if let intensity = flare.maxXrlong {
            return "Flare: \(formatFlux(intensity))"
        }
        return "Solar Flare"
    }
    
    private func buildFlareDetails(flare: GOESXRayFlare) -> String {
        var parts: [String] = []
        
        // Time info
        if let beginTime = flare.beginTime, let beginClass = flare.beginClass {
            parts.append("Start: \(formatTime(beginTime)) (\(beginClass))")
        } else if let beginTime = flare.beginTime {
            parts.append("Start: \(formatTime(beginTime))")
        }
        
        if let maxTime = flare.maxTime, let maxClass = flare.maxClass {
            parts.append("Peak: \(formatTime(maxTime)) (\(maxClass))")
        }
        
        if let endTime = flare.endTime, let endClass = flare.endClass {
            parts.append("End: \(formatTime(endTime)) (\(endClass))")
        } else if let endTime = flare.endTime {
            parts.append("End: \(formatTime(endTime))")
        }
        
        if let satellite = flare.satellite {
            parts.append("GOES-\(satellite)")
        }
        
        return parts.joined(separator: " • ")
    }
    
    private func formatFlux(_ value: Double) -> String {
        if value >= 1e-4 {
            return String(format: "%.1e W/m²", value)
        }
        return String(format: "%.2e W/m²", value)
    }
    
    private func formatTime(_ dateString: String) -> String {
        if let date = parseDate(dateString) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        return dateString.suffix(8).description
    }
    
    private func determineFlareSeverity(flareClass: String) -> SpaceWeatherEvent.EventSeverity {
        let upper = flareClass.uppercased()
        if upper.hasPrefix("X") { return .extreme }
        if upper.hasPrefix("M") { return .high }
        if upper.hasPrefix("C") { return .moderate }
        // B and A class flares are weak
        return .weak
    }
    
    // MARK: - SWPC Alerts
    
    /// Fetch recent SWPC space weather alerts
    func fetchAlerts() async throws -> [SWPCAlert] {
        guard let url = URL(string: alertsURL) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        let alerts = try decoder.decode([SWPCAlert].self, from: data)
        return alerts
    }
    
    /// Convert SWPC alerts to unified SpaceWeatherEvent format
    /// Excludes flare alerts since those come from the GOES X-ray flares endpoint
    func fetchUnifiedAlerts(excludeFlares: Bool = true) async throws -> [SpaceWeatherEvent] {
        let alerts = try await fetchAlerts()
        return alerts.compactMap { alert -> SpaceWeatherEvent? in
            guard let issueTime = parseDate(alert.issueDatetime) else { return nil }
            
            let (type, severity, title) = parseAlertMessage(alert.message, productId: alert.productId)
            
            // Skip flare alerts if we're getting them from GOES endpoint
            if excludeFlares && type == .solarFlare {
                return nil
            }
            
            let details = cleanAlertMessage(alert.message)
            
            return SpaceWeatherEvent(
                id: "swpc-\(alert.productId)-\(alert.issueDatetime)",
                type: type,
                date: issueTime,
                title: title,
                details: details,
                severity: severity,
                link: nil,
                source: .swpc
            )
        }
    }
    
    private func parseAlertMessage(_ message: String, productId: String) -> (SpaceWeatherEventType, SpaceWeatherEvent.EventSeverity, String) {
        // Parse product ID patterns
        // XM5A = X-ray M5 Alert (real-time), XM5S = X-ray M5 Summary (final)
        // K05W = K-index 5 Warning, etc.
        let id = productId.uppercased()
        
        // X-ray flare alerts/summaries
        if id.hasPrefix("X") || message.contains("X-ray") || message.contains("X-Ray") {
            // Check if this is a SUMMARY (has final X-ray Class)
            if let flareClass = extractFlareClass(from: message) {
                let severity = determineFlareSeverity(flareClass: flareClass)
                return (.solarFlare, severity, "Flare: \(flareClass)")
            }
            
            // This is an ALERT (real-time, threshold crossed, no final class yet)
            // Show which threshold was exceeded
            if message.contains("exceeded X") || id.contains("XX") {
                return (.solarFlare, .extreme, "X-Class Flare (ongoing)")
            }
            if message.contains("exceeded M5") || id.contains("XM5") {
                return (.solarFlare, .high, "M5+ Flare (ongoing)")
            }
            if message.contains("exceeded M") || id.contains("XM") {
                return (.solarFlare, .high, "M-Class Flare (ongoing)")
            }
            return (.solarFlare, .moderate, "Solar Flare Alert")
        }
        
        // K-index / Geomagnetic alerts (no severity labels - only flares get those)
        if id.hasPrefix("K") || message.contains("K-index") || message.contains("Geomagnetic") {
            let title: String
            
            if message.contains("K-index of 7") || message.contains("K07") || id.contains("K07") {
                title = "G3+ Geomagnetic Storm"
            } else if message.contains("K-index of 6") || message.contains("K06") || id.contains("K06") {
                title = "G2 Geomagnetic Storm"
            } else if message.contains("K-index of 5") || message.contains("K05") || id.contains("K05") {
                title = "G1 Geomagnetic Storm"
            } else if message.contains("K-index of 4") || message.contains("K04") || id.contains("K04") {
                title = "K4 Geomagnetic Activity"
            } else {
                title = "Geomagnetic Activity"
            }
            return (.geomagneticStorm, .none, title)
        }
        
        // Radio emission alerts
        if id.hasPrefix("TI") || message.contains("Type II") || message.contains("Type IV") {
            if message.contains("Type IV") {
                return (.cme, .none, "Type IV Radio Emission")
            }
            return (.cme, .none, "Type II Radio Emission")
        }
        
        // Electron flux alerts
        if id.hasPrefix("EF") || message.contains("Electron") {
            return (.radiationBeltEnhancement, .none, "Electron Flux Alert")
        }
        
        // 10cm radio burst
        if id.hasPrefix("BH") || message.contains("10cm Radio") {
            return (.solarFlare, .moderate, "10cm Radio Burst")
        }
        
        // Geomagnetic storm watch
        if id.hasPrefix("A") || message.contains("WATCH") {
            if message.contains("G3") {
                return (.geomagneticStorm, .none, "G3 Storm Watch")
            }
            if message.contains("G2") {
                return (.geomagneticStorm, .none, "G2 Storm Watch")
            }
            if message.contains("G1") {
                return (.geomagneticStorm, .none, "G1 Storm Watch")
            }
            return (.geomagneticStorm, .none, "Geomagnetic Watch")
        }
        
        return (.activeRegion, .none, "Space Weather Alert")
    }
    
    /// Extract flare class (e.g., "X1.2", "M5.0", "C3.4") from alert message
    /// Only returns a class if it's the FINAL class, not a threshold
    private func extractFlareClass(from message: String) -> String? {
        // Look for "X-ray Class: M7.1" format - this is the final class in summaries
        // This pattern is specific and won't match threshold mentions like "exceeded M5"
        let xrayClassPattern = "X-ray Class:\\s*([XMCB]\\d+\\.?\\d*)"
        if let regex = try? NSRegularExpression(pattern: xrayClassPattern, options: .caseInsensitive) {
            let range = NSRange(message.startIndex..., in: message)
            if let match = regex.firstMatch(in: message, options: [], range: range) {
                if let matchRange = Range(match.range(at: 1), in: message) {
                    return String(message[matchRange]).uppercased()
                }
            }
        }
        
        // No fallback - only return a class if we found "X-ray Class:" explicitly
        // This prevents matching "M5" from "exceeded M5"
        return nil
    }
    
    private func cleanAlertMessage(_ message: String) -> String {
        // Clean up carriage returns but preserve line breaks for readability
        let cleaned = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Return full message - no truncation
        return cleaned
    }
    
    // MARK: - Solar Probabilities Forecast
    
    /// Fetch SWPC solar flare probability forecast for the next 24-72 hours
    func fetchFlareProbabilities() async throws -> FlareProbabilityForecast {
        guard let url = URL(string: solarProbabilitiesURL) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        // Decode as array of probabilities (sorted by date, most recent first)
        do {
            let probabilities = try decoder.decode([SolarProbabilities].self, from: data)
            
            // Get first entry (most recent forecast = next 24 hours)
            if let first = probabilities.first {
                return FlareProbabilityForecast(
                    cClassProbability: first.cClass1Day ?? 0,
                    mClassProbability: first.mClass1Day ?? 0,
                    xClassProbability: first.xClass1Day ?? 0,
                    protonEventProbability: first.protons1Day ?? 0,
                    fetchedAt: Date()
                )
            }
        } catch {
            // Decoding failed, return unavailable
        }
        
        return .unavailable
    }
    
    // MARK: - X-Ray Flux Time Series
    
    /// Fetch SXR B (1-8Å) flux data for a given time range in hours
    /// Uses appropriate endpoint based on duration: 1-day (<=24h), 3-day (<=72h), or 7-day
    func fetchXRayFluxB(hoursBack: Int) async throws -> [XRayFluxDataPoint] {
        // Choose appropriate endpoint based on time range
        let urlString: String
        if hoursBack <= 24 {
            urlString = xrayFlux1DayURL
        } else if hoursBack <= 72 {
            urlString = xrayFlux3DayURL
        } else {
            urlString = xrayFlux7DayURL
        }
        
        guard let url = URL(string: urlString) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        let allPoints = try decoder.decode([XRayFluxDataPoint].self, from: data)
        
        // Filter for SXR B (0.1-0.8nm / 1-8Å) only - this is the standard for flare classification
        let sxrBPoints = allPoints.filter { $0.energy == sxrBEnergyBand }
        
        // Further filter by time if needed
        let cutoffDate = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: Date()) ?? Date()
        let filteredPoints = sxrBPoints.filter { point in
            guard let date = point.date else { return false }
            return date >= cutoffDate
        }
        
        return filteredPoints
    }

    /// Fetch SXR A (0.5-4Å) flux data for a given time range in hours
    func fetchXRayFluxA(hoursBack: Int) async throws -> [XRayFluxDataPoint] {
        // Choose appropriate endpoint based on time range
        let urlString: String
        if hoursBack <= 24 {
            urlString = xrayFlux1DayURL
        } else if hoursBack <= 72 {
            urlString = xrayFlux3DayURL
        } else {
            urlString = xrayFlux7DayURL
        }
        
        guard let url = URL(string: urlString) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        let allPoints = try decoder.decode([XRayFluxDataPoint].self, from: data)
        
        // Filter for SXR A (0.05-0.4nm / 0.5-4Å) - shorter wavelength
        let sxrAPoints = allPoints.filter { $0.energy == sxrAEnergyBand }
        
        // Further filter by time if needed
        let cutoffDate = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: Date()) ?? Date()
        let filteredPoints = sxrAPoints.filter { point in
            guard let date = point.date else { return false }
            return date >= cutoffDate
        }
        
        return filteredPoints
    }

    /// Fetch both SXR-A and SXR-B data together (more efficient - single request)
    func fetchXRayFluxBoth(hoursBack: Int) async throws -> (sxrA: [XRayFluxDataPoint], sxrB: [XRayFluxDataPoint]) {
        let urlString: String
        if hoursBack <= 24 {
            urlString = xrayFlux1DayURL
        } else if hoursBack <= 72 {
            urlString = xrayFlux3DayURL
        } else {
            urlString = xrayFlux7DayURL
        }
        
        guard let url = URL(string: urlString) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        let allPoints = try decoder.decode([XRayFluxDataPoint].self, from: data)
        let cutoffDate = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: Date()) ?? Date()
        
        let sxrA = allPoints.filter { $0.energy == sxrAEnergyBand }.filter { point in
            guard let date = point.date else { return false }
            return date >= cutoffDate
        }
        
        let sxrB = allPoints.filter { $0.energy == sxrBEnergyBand }.filter { point in
            guard let date = point.date else { return false }
            return date >= cutoffDate
        }
        
        return (sxrA, sxrB)
    }
    
    /// Fetch 7-day X-ray flux time series (legacy - returns both channels)
    func fetchXRayFlux7Day() async throws -> [XRayFluxDataPoint] {
        guard let url = URL(string: xrayFlux7DayURL) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        let points = try decoder.decode([XRayFluxDataPoint].self, from: data)
        return points
    }

    /// Fetch 6-hour X-ray flux time series
    func fetchXRayFlux6Hour() async throws -> [XRayFluxDataPoint] {
        guard let url = URL(string: xrayFlux6HourURL) else {
            throw SWPCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SWPCError.invalidResponse
        }
        
        let points = try decoder.decode([XRayFluxDataPoint].self, from: data)
        return points
    }
    
    // MARK: - Date Parsing
    
    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        // Try ISO8601 format
        let iso8601 = ISO8601DateFormatter()
        if let date = iso8601.date(from: dateString) {
            return date
        }
        
        // Try custom format: "2025-12-31 14:25:30.397"
        let customFormatter = DateFormatter()
        customFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        customFormatter.timeZone = TimeZone(identifier: "UTC")
        if let date = customFormatter.date(from: dateString) {
            return date
        }
        
        // Try without milliseconds
        customFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = customFormatter.date(from: dateString) {
            return date
        }
        
        // Try T separator with Z
        customFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        if let date = customFormatter.date(from: dateString) {
            return date
        }
        
        return nil
    }
}

// MARK: - Error Types

enum SWPCError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid SWPC API URL"
        case .invalidResponse: return "Invalid response from SWPC"
        case .decodingError(let error): return "Failed to decode: \(error.localizedDescription)"
        }
    }
}

// MARK: - GOES X-Ray Flare Model

struct GOESXRayFlare: Codable, Sendable {
    let timeTag: String?
    let satellite: Int?
    let currentClass: String?
    let currentRatio: Double?
    let currentIntXrlong: Double?
    let beginTime: String?
    let beginClass: String?
    let maxTime: String?
    let maxClass: String?
    let maxXrlong: Double?
    let endTime: String?
    let endClass: String?
    
    enum CodingKeys: String, CodingKey {
        case timeTag = "time_tag"
        case satellite
        case currentClass = "current_class"
        case currentRatio = "current_ratio"
        case currentIntXrlong = "current_int_xrlong"
        case beginTime = "begin_time"
        case beginClass = "begin_class"
        case maxTime = "max_time"
        case maxClass = "max_class"
        case maxXrlong = "max_xrlong"
        case endTime = "end_time"
        case endClass = "end_class"
    }
}

// MARK: - SWPC Alert Model

struct SWPCAlert: Codable, Sendable {
    let productId: String
    let issueDatetime: String
    let message: String
    
    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case issueDatetime = "issue_datetime"
        case message
    }
}

// MARK: - X-Ray Flux Data Point

struct XRayFluxDataPoint: Codable, Sendable, Identifiable {
    let timeTag: String
    let satellite: Int?
    let flux: Double?  // X-ray flux in W/m²
    let energy: String?  // Wavelength band (e.g., "0.1-0.8nm")
    
    var id: String { timeTag }
    
    var date: Date? {
        let iso8601 = ISO8601DateFormatter()
        return iso8601.date(from: timeTag)
    }
    
    /// Estimated flare class based on flux value
    var estimatedClass: String {
        guard let flux = flux else { return "?" }
        
        if flux >= 1e-4 { 
            let val = flux / 1e-4
            return String(format: "X%.1f", val)
        }
        if flux >= 1e-5 { 
            let val = flux / 1e-5
            return String(format: "M%.1f", val)
        }
        if flux >= 1e-6 { 
            let val = flux / 1e-6
            return String(format: "C%.1f", val)
        }
        if flux >= 1e-7 { 
            let val = flux / 1e-7
            return String(format: "B%.1f", val)
        }
        return "A"
    }
    
    enum CodingKeys: String, CodingKey {
        case timeTag = "time_tag"
        case satellite
        case flux
        case energy
    }
}

// MARK: - Solar Probabilities Model

/// SWPC Solar Flare Probability Forecast
struct SolarProbabilities: Codable, Sendable {
    let date: String?
    // Day 1 forecasts (next 24 hours)
    let cClass1Day: Int?
    let mClass1Day: Int?
    let xClass1Day: Int?
    let protons1Day: Int?
    // Day 2 forecasts
    let cClass2Day: Int?
    let mClass2Day: Int?
    let xClass2Day: Int?
    let protons2Day: Int?
    // Day 3 forecasts
    let cClass3Day: Int?
    let mClass3Day: Int?
    let xClass3Day: Int?
    let protons3Day: Int?
    
    let polarCapAbsorption: String?
    
    enum CodingKeys: String, CodingKey {
        case date
        case cClass1Day = "c_class_1_day"
        case mClass1Day = "m_class_1_day"
        case xClass1Day = "x_class_1_day"
        case protons1Day = "10mev_protons_1_day"
        case cClass2Day = "c_class_2_day"
        case mClass2Day = "m_class_2_day"
        case xClass2Day = "x_class_2_day"
        case protons2Day = "10mev_protons_2_day"
        case cClass3Day = "c_class_3_day"
        case mClass3Day = "m_class_3_day"
        case xClass3Day = "x_class_3_day"
        case protons3Day = "10mev_protons_3_day"
        case polarCapAbsorption = "polar_cap_absorption"
    }
}

/// Flare probability forecast data for display
struct FlareProbabilityForecast: Sendable {
    let cClassProbability: Int  // C-class (minor)
    let mClassProbability: Int  // M-class (moderate)
    let xClassProbability: Int  // X-class (major)
    let protonEventProbability: Int
    let fetchedAt: Date
    
    static let unavailable = FlareProbabilityForecast(
        cClassProbability: 0,
        mClassProbability: 0,
        xClassProbability: 0,
        protonEventProbability: 0,
        fetchedAt: .distantPast
    )
    
    var hasData: Bool {
        fetchedAt != .distantPast
    }
}
