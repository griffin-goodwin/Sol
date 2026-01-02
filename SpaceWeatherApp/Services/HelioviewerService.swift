import Foundation

/// Service for fetching space weather data from Helioviewer API
/// Documentation: https://api.helioviewer.org/docs/v2/
actor HelioviewerService {
    // Helioviewer API base URL - No API key required!
    private let baseURL = "https://api.helioviewer.org/v2"
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }
    
    // MARK: - Date Helpers
    
    private func isoDateString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
    
    // MARK: - Events API
    
    /// Fetch solar events from HEK (Heliophysics Event Knowledgebase)
    /// Now supports date range for multi-day queries
    func fetchEvents(startDate: Date, endDate: Date, sources: [String] = ["HEK"]) async throws -> HelioviewerEventsResponse {
        let startStr = isoDateString(from: startDate)
        let endStr = isoDateString(from: endDate)
        
        let sourcesStr = sources.joined(separator: ",")
        // Use startTime and endTime as required by Helioviewer API v2
        let urlString = "\(baseURL)/events/?startTime=\(startStr)&endTime=\(endStr)&sources=\(sourcesStr)"
        
        print("🌐 Fetching events from Helioviewer: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw HelioviewerError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HelioviewerError.invalidResponse
        }
        
        print("📊 Response Status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw HelioviewerError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let events = try decoder.decode([HelioviewerEventCategory].self, from: data)
        print("✅ Decoded \(events.count) event categories")
        return HelioviewerEventsResponse(categories: events)
    }
    
    /// Fetch events for a single day (backwards compatibility)
    func fetchEvents(date: Date = Date(), sources: [String] = ["HEK"]) async throws -> HelioviewerEventsResponse {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return try await fetchEvents(startDate: startOfDay, endDate: endOfDay, sources: sources)
    }
    
    // MARK: - Convert to Unified Events
    
    /// Fetch unified events for a time range (in hours before now)
    func fetchUnifiedEvents(hoursBack: Int) async throws -> [SpaceWeatherEvent] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-Double(hoursBack) * 3600)
        let response = try await fetchEvents(startDate: startDate, endDate: endDate)
        return convertToUnifiedEvents(from: response)
    }
    
    /// Fetch unified events for a specific date range
    func fetchUnifiedEvents(startDate: Date, endDate: Date) async throws -> [SpaceWeatherEvent] {
        let response = try await fetchEvents(startDate: startDate, endDate: endDate)
        return convertToUnifiedEvents(from: response)
    }
    
    /// Fetch unified events for a specific date (backwards compatibility)
    func fetchUnifiedEvents(date: Date = Date()) async throws -> [SpaceWeatherEvent] {
        let response = try await fetchEvents(date: date)
        return convertToUnifiedEvents(from: response)
    }
    
    /// Convert Helioviewer response to unified events
    private func convertToUnifiedEvents(from response: HelioviewerEventsResponse) -> [SpaceWeatherEvent] {
        var events: [SpaceWeatherEvent] = []
        
        for category in response.categories {
            // Skip event types we don't want to track (sigmoids, filaments, etc.)
            guard let eventType = mapEventType(from: category.pin) else {
                continue
            }
            
            for group in category.groups {
                for item in group.data {
                    if let startTime = item.startTime ?? item.eventPeakTime,
                       let eventDate = parseDate(startTime) {
                        let severity = determineSeverity(category: category.pin, item: item)
                        let title = buildTitle(category: category, item: item)
                        let details = buildDetails(item: item)
                        let coords = item.parsedCoordinates
                        let x = item.hpcX ?? coords?.x
                        let y = item.hpcY ?? coords?.y
                        
                        // Extract peak intensity for flares without class
                        let intensity = item.peakFlux ?? item.intensity
                        
                        let event = SpaceWeatherEvent(
                            id: item.id ?? UUID().uuidString,
                            type: eventType,
                            date: eventDate,
                            title: title,
                            details: details,
                            severity: severity,
                            link: item.hpcUrl,
                            hpcX: x,
                            hpcY: y,
                            source: .hek,
                            peakIntensity: intensity
                        )
                        events.append(event)
                    }
                }
            }
        }
        
        print("✨ Converted \(events.count) unified events")
        return events.sorted { $0.date > $1.date }
    }
    
    private func mapEventType(from pin: String) -> SpaceWeatherEventType? {
        switch pin.uppercased() {
        case "AR": return .activeRegion
        case "FL", "FLA": return .solarFlare
        case "CE", "CME": return .cme
        default: return nil // Only allow AR, Flares, and CMEs
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            ISO8601DateFormatter(),
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        // Try custom format
        let customFormatter = DateFormatter()
        customFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return customFormatter.date(from: dateString.replacingOccurrences(of: "Z", with: ""))
    }
    
    private func determineSeverity(category: String, item: HelioviewerEventData) -> SpaceWeatherEvent.EventSeverity {
        // For flares, check class
        if let flareClass = item.flClass?.uppercased() {
            if flareClass.hasPrefix("X") { return .extreme }
            if flareClass.hasPrefix("M") { return .high }
            if flareClass.hasPrefix("C") { return .moderate }
            // B and A class flares are weak
            return .weak
        }
        
        // Non-flare events don't get severity labels
        return .none
    }
    
    private func buildTitle(category: HelioviewerEventCategory, item: HelioviewerEventData) -> String {
        if let flClass = item.flClass {
            return "\(category.name): \(flClass)"
        }
        if let arNoaa = item.arNoaa, arNoaa > 0 {
            return "\(category.name) \(arNoaa)"
        }
        return category.name
    }
    
    private func buildDetails(item: HelioviewerEventData) -> String {
        var details = ""
        if let hpc = item.hpcCoord {
            details += "Location: \(hpc) "
        }
        if let area = item.areaAtDiskCenter {
            details += "Area: \(area) "
        }
        return details.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - SDO Screenshot API
    
    /// Generate a screenshot URL for SDO imagery
    /// Layer format: [Observatory,Instrument,Detector,Measurement,Visible,Opacity]
    /// SDO AIA wavelengths: 94, 131, 171, 193, 211, 304, 335, 1600, 1700, 4500
    func getSDOImageURL(
        date: Date = Date(),
        wavelength: SDOWavelength = .aia193,
        width: Int = 1024,
        height: Int = 1024,
        scale: Bool = false,
        watermark: Bool = false
    ) -> URL? {
        let dateStr = isoDateString(from: date)
        let layers = "[\(wavelength.layerString)]"
        
        // Image scale in arcseconds per pixel (2.4 is good for full sun view)
        let imageScale = 2.4204409
        
        var urlString = "\(baseURL)/takeScreenshot/?"
        urlString += "date=\(dateStr)"
        urlString += "&imageScale=\(imageScale)"
        urlString += "&layers=\(layers)"
        urlString += "&x0=0&y0=0"
        urlString += "&width=\(width)&height=\(height)"
        urlString += "&display=true"
        urlString += "&scale=\(scale)"
        urlString += "&watermark=\(watermark)"
        
        return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
    }
    
    /// Generate a screenshot URL for SOHO LASCO C2/C3 (coronagraph) imagery
    func getLASCOImageURL(
        date: Date = Date(),
        instrument: SolarInstrument = .sohoLASCO_C2,
        width: Int = 1024,
        height: Int = 1024,
        scale: Bool = false,
        watermark: Bool = false
    ) -> URL? {
        let dateStr = isoDateString(from: date)
        let layers = "[\(instrument.layerString)]"
        
        // LASCO has wider field of view - use appropriate scale
        let imageScale = instrument.imageScale
        
        var urlString = "\(baseURL)/takeScreenshot/?"
        urlString += "date=\(dateStr)"
        urlString += "&imageScale=\(imageScale)"
        urlString += "&layers=\(layers)"
        urlString += "&x0=0&y0=0"
        urlString += "&width=\(width)&height=\(height)"
        urlString += "&display=true"
        urlString += "&scale=\(scale)"
        urlString += "&watermark=\(watermark)"
        
        return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
    }
    
    /// Get the closest JP2 image info with WCS header data
    func getClosestImage(date: Date, sourceId: Int) async throws -> ClosestImageResponse {
        let dateStr = isoDateString(from: date)
        let urlString = "\(baseURL)/getClosestImage/?date=\(dateStr)&sourceId=\(sourceId)"
        
        guard let url = URL(string: urlString) else {
            throw HelioviewerError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HelioviewerError.invalidResponse
        }
        
        return try decoder.decode(ClosestImageResponse.self, from: data)
    }
    
    /// Get WCS parameters for the current image
    func getImageWCS(date: Date, wavelength: SDOWavelength) async -> SolarWCS? {
        do {
            let imageInfo = try await getClosestImage(date: date, sourceId: wavelength.sourceId)
            
            // The screenshot uses fixed imageScale of 2.4204409 arcsec/pixel
            // and is centered at x0=0, y0=0 (Sun center) with 1024x1024 pixels
            let screenshotScale = 2.4204409
            let screenshotWidth = 1024.0
            let screenshotHeight = 1024.0
            
            return SolarWCS(
                crpix1: screenshotWidth / 2.0,  // Reference pixel at center
                crpix2: screenshotHeight / 2.0,
                crval1: 0.0,  // Sun center in HPC
                crval2: 0.0,
                cdelt1: screenshotScale,  // arcsec per pixel
                cdelt2: screenshotScale,
                rsun: imageInfo.rsun ?? (960.0 / screenshotScale),  // Solar radius in pixels
                naxis1: Int(screenshotWidth),
                naxis2: Int(screenshotHeight)
            )
        } catch {
            print("⚠️ Could not get WCS: \(error), using defaults")
            // Fallback to default values
            return SolarWCS(
                crpix1: 512.0,
                crpix2: 512.0,
                crval1: 0.0,
                crval2: 0.0,
                cdelt1: 2.4204409,
                cdelt2: 2.4204409,
                rsun: 396.5,
                naxis1: 1024,
                naxis2: 1024
            )
        }
    }
    
    // MARK: - Generic Instrument Image
    
    /// Get image URL for any supported instrument
    func getInstrumentImageURL(
        date: Date = Date(),
        instrument: SolarInstrument,
        wavelength: SDOWavelength? = nil,
        width: Int = 1024,
        height: Int = 1024
    ) -> URL? {
        let dateStr = isoDateString(from: date)
        
        // Use wavelength layer for AIA, otherwise use instrument layer
        let layers: String
        if instrument == .sdoAIA, let wl = wavelength {
            layers = "[\(wl.layerString)]"
        } else {
            layers = "[\(instrument.layerString)]"
        }
        
        var urlString = "\(baseURL)/takeScreenshot/?"
        urlString += "date=\(dateStr)"
        urlString += "&imageScale=\(instrument.imageScale)"
        urlString += "&layers=\(layers)"
        urlString += "&x0=0&y0=0"
        urlString += "&width=\(width)&height=\(height)"
        urlString += "&display=true"
        urlString += "&scale=false"
        urlString += "&watermark=false"
        
        return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
    }
    
    // MARK: - Animation Frames
    
    /// Get multiple image URLs for creating an animation
    /// Returns an array of (date, url) tuples for the specified time range
    func getAnimationFrameURLs(
        instrument: SolarInstrument,
        wavelength: SDOWavelength? = nil,
        startDate: Date,
        endDate: Date,
        frameCount: Int = 24,
        width: Int = 512,
        height: Int = 512
    ) -> [(date: Date, url: URL)] {
        var frames: [(date: Date, url: URL)] = []
        
        let totalDuration = endDate.timeIntervalSince(startDate)
        let frameInterval = totalDuration / Double(frameCount - 1)
        
        for i in 0..<frameCount {
            let frameDate = startDate.addingTimeInterval(frameInterval * Double(i))
            if let url = getInstrumentImageURL(
                date: frameDate,
                instrument: instrument,
                wavelength: wavelength,
                width: width,
                height: height
            ) {
                frames.append((date: frameDate, url: url))
            }
        }
        
        return frames
    }
    
    // MARK: - Data Sources
    
    /// Get available data sources (SDO, SOHO, etc.)
    func getDataSources() async throws -> DataSourcesResponse {
        let urlString = "\(baseURL)/getDataSources/?verbose=true"
        
        guard let url = URL(string: urlString) else {
            throw HelioviewerError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HelioviewerError.invalidResponse
        }
        
        // The response is a complex nested structure, we'll decode what we need
        return try decoder.decode(DataSourcesResponse.self, from: data)
    }
}

// MARK: - Solar Instruments

/// Different solar observing instruments available via Helioviewer
enum SolarInstrument: String, CaseIterable, Identifiable, Sendable {
    case sdoAIA = "SDO"
    case sohoLASCO_C2 = "LASCO C2"
    case sohoLASCO_C3 = "LASCO C3"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .sdoAIA: return "SDO"
        case .sohoLASCO_C2: return "SOHO LASCO C2"
        case .sohoLASCO_C3: return "SOHO LASCO C3"
        }
    }
    
    var description: String {
        switch self {
        case .sdoAIA: return "Full-disk solar images in multiple wavelengths"
        case .sohoLASCO_C2: return "Inner corona (2-6 solar radii) - Great for CMEs"
        case .sohoLASCO_C3: return "Outer corona (3.7-30 solar radii) - Wide field CMEs"
        }
    }
    
    var icon: String {
        switch self {
        case .sdoAIA: return "sun.max.fill"
        case .sohoLASCO_C2: return "circle.dashed"
        case .sohoLASCO_C3: return "circles.hexagonpath"
        }
    }
    
    var color: String {
        switch self {
        case .sdoAIA: return "orange"
        case .sohoLASCO_C2: return "blue"
        case .sohoLASCO_C3: return "purple"
        }
    }
    
    /// Layer string for Helioviewer API
    var layerString: String {
        switch self {
        case .sdoAIA: return "SDO,AIA,AIA,171,1,100"  // Default to 171
        case .sohoLASCO_C2: return "SOHO,LASCO,C2,white-light,1,100"
        case .sohoLASCO_C3: return "SOHO,LASCO,C3,white-light,1,100"
        }
    }
    
    /// Source ID for getClosestImage API
    var sourceId: Int {
        switch self {
        case .sdoAIA: return 10  // AIA 171
        case .sohoLASCO_C2: return 0
        case .sohoLASCO_C3: return 3
        }
    }
    
    /// Image scale in arcsec/pixel for full view
    var imageScale: Double {
        switch self {
        case .sdoAIA: return 2.4204409  // Full sun fits in 1024px
        case .sohoLASCO_C2: return 11.9  // ~6 solar radii field of view
        case .sohoLASCO_C3: return 56.0  // ~30 solar radii field of view
        }
    }
    
    /// Whether this instrument has wavelength options
    var hasWavelengthOptions: Bool {
        self == .sdoAIA
    }
}

// MARK: - SDO Wavelengths

enum SDOWavelength: String, CaseIterable, Identifiable, Sendable {
    case aia94 = "94 Å"
    case aia131 = "131 Å"
    case aia171 = "171 Å"
    case aia193 = "193 Å"
    case aia211 = "211 Å"
    case aia304 = "304 Å"
    case aia335 = "335 Å"
    case aia1600 = "1600 Å"
    case aia1700 = "1700 Å"
    case hmiMag = "Magnetogram"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .aia94: return "AIA 94 Å (Fe XVIII)"
        case .aia131: return "AIA 131 Å (Fe VIII, XXI)"
        case .aia171: return "AIA 171 Å (Fe IX)"
        case .aia193: return "AIA 193 Å (Fe XII, XXIV)"
        case .aia211: return "AIA 211 Å (Fe XIV)"
        case .aia304: return "AIA 304 Å (He II)"
        case .aia335: return "AIA 335 Å (Fe XVI)"
        case .aia1600: return "AIA 1600 Å (C IV)"
        case .aia1700: return "AIA 1700 Å (Continuum)"
        case .hmiMag: return "HMI Magnetogram"
        }
    }
    
    var description: String {
        switch self {
        case .aia94: return "Flaring regions (Fe XVIII) — 6.3 million K"
        case .aia131: return "Flaring regions (Fe VIII, XX, XXIII) — 400K to 16 million K"
        case .aia171: return "Quiet corona, upper transition region (Fe IX) — 630,000 K"
        case .aia193: return "Corona and hot flare plasma (Fe XII, XXIV) — 1.2 to 20 million K"
        case .aia211: return "Active region corona (Fe XIV) — 2 million K"
        case .aia304: return "Chromosphere and transition region (He II) — 50,000 K"
        case .aia335: return "Active region corona (Fe XVI) — 2.5 million K"
        case .aia1600: return "Transition region and upper photosphere (C IV) — 100,000 K"
        case .aia1700: return "Temperature minimum, photosphere (continuum) — 5,000 K"
        case .hmiMag: return "Photospheric magnetic field strength and polarity"
        }
    }
    
    var color: String {
        switch self {
        case .aia94: return "green"
        case .aia131: return "teal"
        case .aia171: return "yellow"
        case .aia193: return "orange"
        case .aia211: return "purple"
        case .aia304: return "red"
        case .aia335: return "blue"
        case .aia1600: return "yellow"
        case .aia1700: return "pink"
        case .hmiMag: return "gray"
        }
    }
    
    /// Layer string for Helioviewer API: [Observatory,Instrument,Detector,Measurement,Visible,Opacity]
    var layerString: String {
        switch self {
        case .aia94: return "SDO,AIA,AIA,94,1,100"
        case .aia131: return "SDO,AIA,AIA,131,1,100"
        case .aia171: return "SDO,AIA,AIA,171,1,100"
        case .aia193: return "SDO,AIA,AIA,193,1,100"
        case .aia211: return "SDO,AIA,AIA,211,1,100"
        case .aia304: return "SDO,AIA,AIA,304,1,100"
        case .aia335: return "SDO,AIA,AIA,335,1,100"
        case .aia1600: return "SDO,AIA,AIA,1600,1,100"
        case .aia1700: return "SDO,AIA,AIA,1700,1,100"
        case .hmiMag: return "SDO,HMI,HMI,magnetogram,1,100"
        }
    }
    
    /// Source ID for getClosestImage API
    var sourceId: Int {
        switch self {
        case .aia94: return 8
        case .aia131: return 9
        case .aia171: return 10
        case .aia193: return 11
        case .aia211: return 12
        case .aia304: return 13
        case .aia335: return 14
        case .aia1600: return 15
        case .aia1700: return 16
        case .hmiMag: return 18
        }
    }
}

// MARK: - Response Models

struct HelioviewerEventsResponse: Sendable {
    let categories: [HelioviewerEventCategory]
}

struct HelioviewerEventCategory: Codable, Sendable {
    let name: String
    let pin: String
    let groups: [HelioviewerEventGroup]
}

struct HelioviewerEventGroup: Codable, Sendable {
    let name: String
    let contact: String?
    let url: String?
    let data: [HelioviewerEventData]
}

struct HelioviewerEventData: Codable, Sendable {
    let id: String?
    let startTime: String?
    let endTime: String?
    let eventPeakTime: String?
    let hpcCoord: String?
    let hpcUrl: String?
    let arNoaa: Int?
    let areaAtDiskCenter: Int?
    let flClass: String?
    let hpcX: Double?
    let hpcY: Double?
    // Flare intensity fields
    let peakFlux: Double?
    let intensity: Double?
    
    enum CodingKeys: String, CodingKey {
        case id = "kb_archivid"
        case startTime = "event_starttime"
        case endTime = "event_endtime"
        case eventPeakTime = "event_peaktime"
        case hpcCoord = "hpc_coord"
        case hpcUrl = "hv_hpc_url"
        case arNoaa = "ar_noaanum"
        case areaAtDiskCenter = "area_atdiskcenter"
        case flClass = "fl_goescls"
        case hpcX = "hpc_x"
        case hpcY = "hpc_y"
        case peakFlux = "fl_peakflux"
        case intensity = "intensity_mean"
    }
    
    // Helper to parse coordinates from string if needed
    var parsedCoordinates: (x: Double, y: Double)? {
        if let hpcCoord = hpcCoord {
            // Format: "POINT(x y)"
            let components = hpcCoord
                .replacingOccurrences(of: "POINT(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .components(separatedBy: " ")
            
            if components.count >= 2,
               let x = Double(components[0]),
               let y = Double(components[1]) {
                return (x, y)
            }
        }
        return nil
    }
}

struct ScreenshotResponse: Codable, Sendable {
    let id: Int
}

struct ClosestImageResponse: Codable, Sendable {
    let id: String
    let date: String
    let name: String
    let scale: Double?
    let width: Int?
    let height: Int?
    let rsun: Double?  // Solar radius in pixels for the original JP2
    let refPixelX: Double?
    let refPixelY: Double?
    let layeringOrder: Int?
}

/// World Coordinate System parameters for solar images
/// Based on FITS WCS standard used in solar physics
struct SolarWCS: Sendable {
    let crpix1: Double  // Reference pixel X (usually image center)
    let crpix2: Double  // Reference pixel Y
    let crval1: Double  // Reference coordinate X (usually 0 = Sun center)
    let crval2: Double  // Reference coordinate Y
    let cdelt1: Double  // Plate scale X (arcsec/pixel)
    let cdelt2: Double  // Plate scale Y (arcsec/pixel)
    let rsun: Double    // Solar radius in pixels
    let naxis1: Int     // Image width
    let naxis2: Int     // Image height
    
    /// Convert Helioprojective Cartesian coordinates (arcsec from Sun center) to normalized view coordinates (0-1)
    func hpcToNormalized(hpcX: Double, hpcY: Double) -> (x: Double, y: Double)? {
        // Convert HPC (arcsec) to pixel coordinates
        // pixel = (hpc - crval) / cdelt + crpix
        let pixelX = (hpcX - crval1) / cdelt1 + crpix1
        let pixelY = (hpcY - crval2) / cdelt2 + crpix2
        
        // Normalize to 0-1 range
        // Note: Image Y axis is inverted (0 at top, increases downward)
        let normalizedX = pixelX / Double(naxis1)
        let normalizedY = 1.0 - (pixelY / Double(naxis2))  // Flip Y
        
        // Check bounds
        guard normalizedX >= 0 && normalizedX <= 1 && normalizedY >= 0 && normalizedY <= 1 else {
            return nil
        }
        
        return (normalizedX, normalizedY)
    }
    
    /// Get the solar radius as a fraction of the image width
    var solarRadiusNormalized: Double {
        return (rsun * 2) / Double(naxis1)
    }
}

struct DataSourcesResponse: Codable, Sendable {
    // Simplified - full response is very complex
}

// MARK: - Errors

enum HelioviewerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP Error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .noData:
            return "No data available"
        }
    }
}
