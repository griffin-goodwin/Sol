import Foundation
import CoreLocation

/// Service for fetching Aurora and geomagnetic data from NOAA
actor AuroraService {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Geocoding cache to avoid redundant API calls and rate limiting
    private var geocodeCache: [String: String] = [:]
    
    // API Endpoints
    private let auroraForecastURL = "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json"
    private let kpIndexURL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"
    private let kpForecastURL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json"
    private let solarWindURL = "https://services.swpc.noaa.gov/products/solar-wind/plasma-7-day.json"
    private let solarWindMagURL = "https://services.swpc.noaa.gov/products/solar-wind/mag-7-day.json"
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }
    
    // MARK: - Aurora Forecast (OVATION Model)
    
    /// Fetch the latest OVATION aurora forecast
    func fetchAuroraForecast() async throws -> AuroraForecast {
        guard let url = URL(string: auroraForecastURL) else {
            throw AuroraServiceError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuroraServiceError.invalidResponse
        }
        
        let forecast = try decoder.decode(AuroraForecast.self, from: data)
        print("✅ Aurora: Fetched OVATION forecast with \(forecast.coordinates.count) data points")
        return forecast
    }
    
func fetchAuroraPoints() async throws -> [AuroraPoint] {
    let forecast = try await fetchAuroraForecast()
    // Quick debug: show first few raw coords and ranges
    let sample = Array(forecast.coordinates.prefix(10))
    print("🔎 OVATION sample coords (first 10): \(sample)")

    // Compute ranges for index 0 and 1 to help detect which is lat vs lon
    let idx0Values = forecast.coordinates.compactMap { $0.count > 0 ? $0[0] : nil }
    let idx1Values = forecast.coordinates.compactMap { $0.count > 1 ? $0[1] : nil }
    if let min0 = idx0Values.min(), let max0 = idx0Values.max(),
       let min1 = idx1Values.min(), let max1 = idx1Values.max() {
        print(String(format: "🔎 index0 range: %.2f .. %.2f, index1 range: %.2f .. %.2f", min0, max0, min1, max1))
    }

    // Decide which index is latitude: prefer the index whose values fall within [-90,90] more strictly
    let idx0InLatRange = idx0Values.allSatisfy { abs($0) <= 90 }
    let idx1InLatRange = idx1Values.allSatisfy { abs($0) <= 90 }
    let latIndex: Int
    let lonIndex: Int

    if idx1InLatRange && !idx0InLatRange {
        latIndex = 1; lonIndex = 0
        print("🔎 Detected ordering: [lon, lat, prob] -> using index 1 as latitude")
    } else if idx0InLatRange && !idx1InLatRange {
        latIndex = 0; lonIndex = 1
        print("🔎 Detected ordering: [lat, lon, prob] -> using index 0 as latitude")
    } else {
        // Ambiguous: assume NOAA format [lon, lat, prob] (most common)
        latIndex = 1; lonIndex = 0
        print("🔎 Ambiguous ordering — defaulting to index 1 as latitude (common OVATION format)")
    }

    return forecast.coordinates.compactMap { coord -> AuroraPoint? in
        // Expect at least [lon, lat, prob]
        guard coord.count >= 3 else { return nil }

        let rawLon = coord[lonIndex]
        // Convert 0..360 -> -180..180 when appropriate
        let longitude: Double
        if rawLon >= 0.0 && rawLon <= 360.0 {
            longitude = rawLon > 180.0 ? rawLon - 360.0 : rawLon
        } else {
            longitude = rawLon
        }

        let latitude = coord[latIndex]
        let probability = coord[2]

        guard probability > 0 else { return nil }
        return AuroraPoint(longitude: longitude, latitude: latitude, probability: probability)
    }
}

func fetchAuroraPoints(hemisphere: Hemisphere) async throws -> [AuroraPoint] {
    let allPoints = try await fetchAuroraPoints()
    switch hemisphere {
    case .north:
        let north = allPoints.filter { $0.latitude >= 0 }
        print("🔎 North points count: \(north.count)")
        return north
    case .south:
        let south = allPoints.filter { $0.latitude < 0 }
        print("🔎 South points count: \(south.count)")
        return south
    }
}
    
    /// Get aurora points filtered by minimum probability
    func fetchAuroraPoints(minProbability: Double) async throws -> [AuroraPoint] {
        let allPoints = try await fetchAuroraPoints()
        return allPoints.filter { $0.probability >= minProbability }
    }
    
    // MARK: - Kp Index
    
    /// Fetch current and recent Kp index values
    func fetchKpIndex() async throws -> [KpIndexPoint] {
        guard let url = URL(string: kpIndexURL) else {
            throw AuroraServiceError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuroraServiceError.invalidResponse
        }
        
        // The API returns array of arrays, need custom parsing
        let rawData = try decoder.decode([[String]].self, from: data)
        
        // Skip header row and parse data
        let points = rawData.dropFirst().compactMap { row -> KpIndexPoint? in
            guard row.count >= 2,
                  let kp = Double(row[1]) else { return nil }
            
            return KpIndexPoint(
                timeTag: row[0],
                kpIndex: kp,
                estimated: row.count > 2 ? row[2] : nil
            )
        }
        
        print("✅ Aurora: Fetched \(points.count) Kp index readings")
        return points
    }
    
    /// Get the current (most recent) Kp index
    func fetchCurrentKp() async throws -> KpIndexPoint? {
        let points = try await fetchKpIndex()
        return points.last
    }

    /// Fetch Kp forecast (array-of-arrays with header). Returns parsed `KpIndexPoint` entries.
    func fetchKpForecast() async throws -> [KpIndexPoint] {
        guard let url = URL(string: kpForecastURL) else {
            throw AuroraServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuroraServiceError.invalidResponse
        }

        // The forecast endpoint returns an array-of-arrays where some cells may be null.
        let rawData = try decoder.decode([[String?]].self, from: data)
        guard rawData.count > 1 else { return [] }

        // Determine header indices
        let header = rawData[0].map { $0?.lowercased() ?? "" }
        let timeIdx = header.firstIndex(of: "time_tag") ?? 0
        let kpIdx = header.firstIndex(of: "kp") ?? 1
        let scaleIdx = header.firstIndex(of: "noaa_scale") ?? 3

        let points = rawData.dropFirst().compactMap { row -> KpIndexPoint? in
            // Read time tag if available
            let timeTag = (row.count > timeIdx ? row[timeIdx] : nil) ?? ""

            // Read raw kp value, tolerate nil/empty and different formatting (commas, whitespace)
            let rawKp = (row.count > kpIdx ? row[kpIdx] : nil) ?? ""
            let kpTrimmed = rawKp.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            let kpVal = Double(kpTrimmed) ?? 0.0

            let scale = (row.count > scaleIdx ? row[scaleIdx] : nil)

            // Require a time tag; keep rows even when kp is empty (use 0.0)
            guard !timeTag.isEmpty else { return nil }

            return KpIndexPoint(timeTag: timeTag, kpIndex: kpVal, estimated: scale)
        }

        print("✅ Aurora: Fetched KP forecast entries: \(points.count)")

        // Debug: print first 12 parsed forecast entries for verification
        if !points.isEmpty {
            print("🔎 KP forecast sample (first \(min(12, points.count))):")
            for (i, p) in points.prefix(12).enumerated() {
                let dateStr = p.date.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
                let est = p.estimated ?? "-"
                print(String(format: "  %2d: time=%@ kp=%.1f est=%@ date=%@", i, p.timeTag, p.kpIndex, est, dateStr))
            }
        }

        return points
    }
    
    // MARK: - Helpers
    
    /// Get maximum aurora probability at a given latitude (approximate)
    func getMaxProbability(at latitude: Double, from points: [AuroraPoint]) -> Double {
        let nearbyPoints = points.filter { abs($0.latitude - latitude) < 2 }
        return nearbyPoints.map { $0.probability }.max() ?? 0
    }
    
    /// Check if aurora might be visible at a coordinate
    func auroraVisibility(at coordinate: (latitude: Double, longitude: Double), points: [AuroraPoint]) -> AuroraIntensity {
        let nearbyPoints = points.filter {
            abs($0.latitude - coordinate.latitude) < 2 &&
            abs($0.longitude - coordinate.longitude) < 5
        }
        
        let maxProb = nearbyPoints.map { $0.probability }.max() ?? 0
        
        switch maxProb {
        case 0..<10: return .none
        case 10..<30: return .low
        case 30..<50: return .moderate
        case 50..<70: return .high
        case 70...: return .extreme
        default: return .none
        }
    }

    // MARK: - Geocoding

    /// Reverse geocode a set of points. Updates the locationName property.
    /// Uses CLGeocoder with rate limiting to avoid throttling.
    /// - Parameter maxNew: Maximum number of new (uncached) geocode requests to make.
    func geocodePoints(_ points: [AuroraPoint], maxNew: Int = 5) async -> [AuroraPoint] {
        let geocoder = CLGeocoder()
        var updatedPoints: [AuroraPoint] = []
        var requestCount = 0

        for point in points {
            var p = point

            // Check cache first (no API call needed)
            if let cachedName = geocodeCache[p.id] {
                p.locationName = cachedName
                updatedPoints.append(p)
                continue
            }

            // Stop making new API calls if we've hit the limit
            if requestCount >= maxNew {
                updatedPoints.append(p)
                continue
            }

            let location = CLLocation(latitude: p.latitude, longitude: p.longitude)
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    let adminArea = placemark.administrativeArea
                    let usableAdmin = adminArea?.localizedCaseInsensitiveContains("unorganized") == true ? nil : adminArea
                    let city = placemark.locality ?? usableAdmin
                    let country = placemark.country

                    let name: String
                    if let city, let country {
                        name = "\(city), \(country)"
                    } else if let country {
                        name = country
                    } else {
                        name = placemark.name ?? "Unknown Location"
                    }

                    p.locationName = name
                    geocodeCache[p.id] = name
                }
                requestCount += 1
            } catch let error as NSError {
                if error.domain == "GEOErrorDomain" && error.code == -3 {
                    // Throttled - stop making requests
                    updatedPoints.append(p)
                    // Append remaining points without geocoding
                    let remaining = points.dropFirst(updatedPoints.count)
                    for var r in remaining {
                        if let cachedName = geocodeCache[r.id] {
                            r.locationName = cachedName
                        }
                        updatedPoints.append(r)
                    }
                    return updatedPoints
                } else if error.domain != "kCLErrorDomain" || error.code != 2 {
                    print("⚠️ Geocoding failed: \(error.localizedDescription)")
                }
            }
            updatedPoints.append(p)

            // Rate limit: 1.5s between requests to stay well within Apple's 50/min limit
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        return updatedPoints
    }
}

// MARK: - Geodesy Helpers

/// Result of look-direction geometry computation
struct GeoLookResult {
    let azimuthDegrees: Double   // bearing from observer -> target (0..360)
    let elevationDegrees: Double // alpha, positive = above horizon
    let surfaceDistanceMeters: Double // great-circle surface distance
}

/// Compute azimuth / elevation / surface distance from observer to target location.
/// - Parameters:
///   - observerLat: observer latitude in degrees
///   - observerLon: observer longitude in degrees
///   - observerAltMeters: observer altitude in meters
///   - targetLat: target latitude in degrees
///   - targetLon: target longitude in degrees
///   - auroraAltitudeMeters: assumed emission altitude in meters (default 110 km)
func computeLookGeometry(observerLat: Double, observerLon: Double, observerAltMeters: Double, targetLat: Double, targetLon: Double, auroraAltitudeMeters h: Double = 110_000.0) -> GeoLookResult {
    let R = 6_371_000.0 // Earth radius in meters

    let φo = observerLat * .pi / 180.0
    let λo = observerLon * .pi / 180.0
    let φa = targetLat * .pi / 180.0
    let λa = targetLon * .pi / 180.0
    let dLon = λa - λo

    // central angle theta (clamp for safety)
    var cosTheta = sin(φo)*sin(φa) + cos(φo)*cos(φa)*cos(dLon)
    if cosTheta > 1.0 { cosTheta = 1.0 }
    if cosTheta < -1.0 { cosTheta = -1.0 }
    let theta = acos(cosTheta)

    // great-circle surface distance
    let s = R * theta

    // radii
    let Ro = R + max(0.0, observerAltMeters)
    let Ra = R + h

    // elevation angle alpha (radians)
    let numerator = Ra * cos(theta) - Ro
    let denominator = Ra * sin(theta)
    let alpha = atan2(numerator, denominator)

    // azimuth (bearing) from observer to target
    let y = sin(dLon) * cos(φa)
    let x = cos(φo)*sin(φa) - sin(φo)*cos(φa)*cos(dLon)
    var az = atan2(y, x) * 180.0 / .pi
    if az < 0 { az += 360.0 }

    return GeoLookResult(
        azimuthDegrees: az,
        elevationDegrees: alpha * 180.0 / .pi,
        surfaceDistanceMeters: s
    )
}

// MARK: - Errors

enum AuroraServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case parsingError
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for aurora data"
        case .invalidResponse:
            return "Invalid response from aurora service"
        case .parsingError:
            return "Failed to parse aurora data"
        case .noData:
            return "No aurora data available"
        }
    }
}
