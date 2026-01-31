import SwiftUI
import CoreLocation

/// Result of look-direction geometry computation plus the point metadata
struct GeoLookResultWithPoint {
    let point: AuroraPoint
    let geometry: GeoLookResult
}

struct AuroraCompassOverlay: View {
    @StateObject private var loc = LocationHeadingManager()
    private let auroraService = AuroraService()
    var auroraPoints: [AuroraPoint]
    var selectedHemisphere: Hemisphere
    var auroraAltitudeMeters: Double = 110_000.0
    var onClose: () -> Void

    @State private var isExpanded = false
    @State private var continuousRotation: Double = 0
    @State private var lastRawHeading: Double? = nil
    @State private var geocodedBestPoint: AuroraPoint? = nil

    var body: some View {
        Group {
            if let observer = loc.location {
                if let bestResult = bestLook(for: observer) {
                    let best = bestResult.geometry
                    let point = geocodedBestPoint ?? bestResult.point

                    VStack(spacing: 0) {
                        if !isExpanded {
                            collapsedView(point: point, geometry: best)
                        } else {
                            expandedView(point: point, best: best)
                        }
                    }
                    .onAppear {
                        updateGeocoding(for: bestResult.point)
                    }
                    .onChange(of: bestResult.point.id) { _ in
                        updateGeocoding(for: bestResult.point)
                    }
                } else {
                    noDataView
                }
            } else {
                enableLocationView
            }
        }
    }

    // MARK: - Collapsed View (Minimal Pill)

    private func collapsedView(point: AuroraPoint, geometry: GeoLookResult) -> some View {
        let viewingChance = calculateViewingProbability(baseProb: point.probability, geometry: geometry)

        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 10) {
                // Mini compass indicator
                ZStack {
                    Circle()
                        .fill(auroraUIColor(for: viewingChance).opacity(0.25))
                        .frame(width: 40, height: 40)

                    Image(systemName: "location.north.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(auroraUIColor(for: viewingChance))
                        .shadow(color: auroraUIColor(for: viewingChance), radius: 4)
                        .rotationEffect(.degrees(continuousRotation))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: continuousRotation)
                        .onChange(of: loc.heading?.trueHeading ?? loc.heading?.magneticHeading ?? 0) { newHeading in
                            updateRotation(newHeading: newHeading, targetAzimuth: geometry.azimuthDegrees)
                        }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(Int(viewingChance))%")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(auroraUIColor(for: viewingChance))

                        Text(cardinalDirection(from: geometry.azimuthDegrees))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    // Show if above or below horizon
                    HStack(spacing: 4) {
                        Image(systemName: geometry.elevationDegrees >= 0 ? "eye" : "eye.slash")
                            .font(.system(size: 9, weight: .bold))
                        Text(geometry.elevationDegrees >= 0 ? "Above horizon" : "Below horizon")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(geometry.elevationDegrees >= 0 ? Theme.auroraGreen : .orange)
                }

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(auroraUIColor(for: viewingChance).opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded View (Full Card)

    private func expandedView(point: AuroraPoint, best: GeoLookResult) -> some View {
        VStack(spacing: 16) {
            // Header with close button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BEST VIEWING DIRECTION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1.2)

                    Text(point.locationName ?? cardinalDirection(from: best.azimuthDegrees))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text(String(format: "%.1f°%@, %.1f°%@",
                                abs(point.latitude), point.latitude >= 0 ? "N" : "S",
                                abs(point.longitude), point.longitude >= 0 ? "E" : "W"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Horizon indicator - prominent
            HStack(spacing: 8) {
                Image(systemName: best.elevationDegrees >= 0 ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 14))

                if best.elevationDegrees >= 0 {
                    Text("Look \(String(format: "%.1f°", best.elevationDegrees)) above the horizon")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("Currently \(String(format: "%.1f°", abs(best.elevationDegrees))) below horizon")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(best.elevationDegrees >= 0 ? Theme.auroraGreen : .orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background((best.elevationDegrees >= 0 ? Theme.auroraGreen : Color.orange).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Compass
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    .frame(width: 130, height: 130)

                // Cardinal markers (outside the ring)
                ForEach(["N", "E", "S", "W"], id: \.self) { dir in
                    Text(dir)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(dir == "N" ? .white : .white.opacity(0.5))
                        .offset(y: -72)
                        .rotationEffect(.degrees(cardinalOffset(dir)))
                }

                // Tick marks (inside the ring, extending inward)
                ForEach(0..<12) { i in
                    Rectangle()
                        .fill(Color.white.opacity(i % 3 == 0 ? 0.4 : 0.15))
                        .frame(width: 1.5, height: i % 3 == 0 ? 10 : 5)
                        .offset(y: -60)
                        .rotationEffect(.degrees(Double(i) * 30))
                }

                // Inner circle
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 90, height: 90)

                // Direction arrow
                Image(systemName: "location.north.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .foregroundStyle(auroraUIColor(for: point.probability))
                    .shadow(color: auroraUIColor(for: point.probability).opacity(0.8), radius: 10)
                    .rotationEffect(.degrees(continuousRotation))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: continuousRotation)
                    .onChange(of: loc.heading?.trueHeading ?? loc.heading?.magneticHeading ?? 0) { newHeading in
                        updateRotation(newHeading: newHeading, targetAzimuth: best.azimuthDegrees)
                    }
            }

            // Stats grid
            HStack(spacing: 0) {
                statItem(
                    value: String(format: "%.0f°", best.azimuthDegrees),
                    label: "Bearing",
                    icon: "safari"
                )

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: 40)

                statItem(
                    value: String(format: "%+.1f°", best.elevationDegrees),
                    label: "Elevation",
                    icon: "scope",
                    valueColor: best.elevationDegrees >= 0 ? Theme.auroraGreen : .orange
                )

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: 40)

                statItem(
                    value: String(format: "%.0f km", best.surfaceDistanceMeters / 1000.0),
                    label: "Distance",
                    icon: "arrow.left.and.right"
                )
            }
            .padding(.vertical, 12)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Your viewing chance
            let viewingChance = calculateViewingProbability(baseProb: point.probability, geometry: best)
            VStack(spacing: 8) {
                HStack {
                    Text("YOUR VIEWING CHANCE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1)

                    Spacer()

                    Text("\(Int(viewingChance))%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(auroraUIColor(for: viewingChance))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        auroraUIColor(for: viewingChance).opacity(0.8),
                                        auroraUIColor(for: viewingChance)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * (viewingChance / 100.0))
                    }
                }
                .frame(height: 6)

                // Show base probability for reference
                Text("Aurora at location: \(Int(point.probability))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(auroraUIColor(for: point.probability).opacity(0.3), lineWidth: 1)
        )
        .frame(width: 290)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
    }

    private func statItem(value: String, label: String, icon: String, valueColor: Color = .white) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(valueColor)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helper Views

    private var noDataView: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .foregroundStyle(Theme.auroraGreen)
            Text("No aurora data")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.3))
        .clipShape(Capsule())
    }

    private var enableLocationView: some View {
        Button(action: { loc.requestAuthorization() }) {
            HStack(spacing: 8) {
                Image(systemName: "location.slash")
                    .foregroundStyle(Theme.auroraGreen)
                Text("Enable Location")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.3))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Calculate personal viewing probability based on aurora probability and viewing geometry
    private func calculateViewingProbability(baseProb: Double, geometry: GeoLookResult) -> Double {
        // If below horizon, can't see it
        guard geometry.elevationDegrees >= -2 else { return 0 }

        // Start with the base NOAA probability
        var viewingProb = baseProb

        // Elevation factor: aurora is best viewed at low angles (5-30°)
        // Below horizon = 0, at horizon = reduced, optimal around 10-20°
        let elevFactor: Double
        if geometry.elevationDegrees < 0 {
            // Just below horizon - very low chance (atmospheric refraction might help slightly)
            elevFactor = 0.1
        } else if geometry.elevationDegrees < 5 {
            // Very low on horizon - haze/obstructions reduce visibility
            elevFactor = 0.5 + (geometry.elevationDegrees / 5.0) * 0.3
        } else if geometry.elevationDegrees < 30 {
            // Optimal viewing range
            elevFactor = 0.8 + (min(geometry.elevationDegrees, 20) / 20.0) * 0.2
        } else {
            // High elevation - still good but aurora typically appears lower
            elevFactor = 0.9
        }
        viewingProb *= elevFactor

        // Distance factor: aurora can be seen from far away, but closer is better
        // Typical visible range is 500-1000+ km
        let distanceKm = geometry.surfaceDistanceMeters / 1000.0
        let distFactor: Double
        if distanceKm < 200 {
            distFactor = 1.0  // Very close - excellent
        } else if distanceKm < 500 {
            distFactor = 0.95 // Close - great
        } else if distanceKm < 1000 {
            distFactor = 0.85 // Moderate - good
        } else if distanceKm < 1500 {
            distFactor = 0.7  // Far - reduced
        } else {
            distFactor = max(0.3, 0.7 - (distanceKm - 1500) / 3000.0)  // Very far - significantly reduced
        }
        viewingProb *= distFactor

        return min(100, max(0, viewingProb))
    }

    private func cardinalDirection(from degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return directions[index]
    }

    private func cardinalOffset(_ dir: String) -> Double {
        switch dir {
        case "N": return 0
        case "E": return 90
        case "S": return 180
        case "W": return 270
        default: return 0
        }
    }

    private func updateRotation(newHeading: Double, targetAzimuth: Double) {
        let targetRotation = targetAzimuth - newHeading

        if lastRawHeading == nil {
            continuousRotation = (targetRotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        } else {
            let currentMod = continuousRotation.truncatingRemainder(dividingBy: 360)
            let targetMod = targetRotation.truncatingRemainder(dividingBy: 360)

            var delta = targetMod - currentMod

            if delta > 180 {
                delta -= 360
            } else if delta < -180 {
                delta += 360
            }

            continuousRotation += delta
        }
        lastRawHeading = newHeading
    }

    private func updateGeocoding(for point: AuroraPoint) {
        if geocodedBestPoint?.id == point.id && geocodedBestPoint?.locationName != nil {
            return
        }

        if let current = geocodedBestPoint {
            let dist = abs(current.latitude - point.latitude) + abs(current.longitude - point.longitude)
            if dist > 0.1 {
                geocodedBestPoint = nil
            }
        }

        Task {
            let updated = await auroraService.geocodePoints([point])
            if let first = updated.first {
                await MainActor.run {
                    self.geocodedBestPoint = first
                }
            }
        }
    }

    private func bestLook(for observer: CLLocation) -> GeoLookResultWithPoint? {
        let obsLat = observer.coordinate.latitude
        let obsLon = observer.coordinate.longitude
        let obsAlt = observer.altitude

        let points = auroraPoints.filter { selectedHemisphere == .north ? $0.latitude >= 0 : $0.latitude < 0 }
        guard !points.isEmpty else { return nil }

        var best: (point: AuroraPoint, score: Double, result: GeoLookResult)? = nil

        for p in points {
            let geo = computeLookGeometry(
                observerLat: obsLat,
                observerLon: obsLon,
                observerAltMeters: obsAlt,
                targetLat: p.latitude,
                targetLon: p.longitude,
                auroraAltitudeMeters: auroraAltitudeMeters
            )
            // Score using personal viewing probability
            let viewingProb = calculateViewingProbability(baseProb: p.probability, geometry: geo)
            if best == nil || viewingProb > best!.score {
                best = (p, viewingProb, geo)
            }
        }

        if let best = best {
            return GeoLookResultWithPoint(point: best.point, geometry: best.result)
        }
        return nil
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            HStack {
                Spacer()
                AuroraCompassOverlay(
                    auroraPoints: [AuroraPoint(longitude: -149, latitude: 64.5, probability: 80)],
                    selectedHemisphere: .north,
                    onClose: {}
                )
                .padding()
            }
        }
    }
}
