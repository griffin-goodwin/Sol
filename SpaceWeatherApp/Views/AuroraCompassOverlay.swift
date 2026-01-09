import SwiftUI
import CoreLocation

struct AuroraCompassOverlay: View {
    @StateObject private var loc = LocationHeadingManager()
    var auroraPoints: [AuroraPoint]
    var selectedHemisphere: Hemisphere
    var auroraAltitudeMeters: Double = 110_000.0

    // Smoothing for heading (simple exponential)
    @State private var smoothHeading: Double = 0

    var body: some View {
        Group {
            if let observer = loc.location {
                if let best = bestLook(for: observer) {
                    VStack(spacing: 8) {
                        // Compass circle with arrow
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 96, height: 96)
                                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))

                            Image(systemName: "location.north.line.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundStyle(Color.yellow)
                                .rotationEffect(.degrees( bestRelativeHeading(for: best, observerHeading: loc.heading?.trueHeading ?? loc.heading?.magneticHeading ?? 0)))
                                .animation(.easeOut(duration: 0.12), value: loc.heading?.trueHeading ?? loc.heading?.magneticHeading ?? 0)
                        }

                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Azimuth: %.0f°", best.azimuthDegrees))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white)
                                Text(String(format: "Elevation: %.1f°", best.elevationDegrees))
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.9))
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.0f km", best.surfaceDistanceMeters / 1000.0))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white)
                                Text("probability: high")
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.8))
                            }
                        }
                        .frame(width: 220)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("No aurora data")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Button(action: { loc.requestAuthorization() }) {
                    Text("Enable Location")
                        .font(.caption)
                        .foregroundStyle(Color.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func bestLook(for observer: CLLocation) -> GeoLookResult? {
        let obsLat = observer.coordinate.latitude
        let obsLon = observer.coordinate.longitude
        let obsAlt = observer.altitude

        // Filter points by hemisphere
        let points = auroraPoints.filter { selectedHemisphere == .north ? $0.latitude >= 0 : $0.latitude < 0 }
        guard !points.isEmpty else { return nil }

        var best: (point: AuroraPoint, score: Double, result: GeoLookResult)? = nil

        for p in points {
            let geo = computeLookGeometry(observerLat: obsLat, observerLon: obsLon, observerAltMeters: obsAlt, targetLat: p.latitude, targetLon: p.longitude, auroraAltitudeMeters: auroraAltitudeMeters)
            // Score: probability * elevation factor (prefer positive elevation)
            let elevFactor = max(0.0, geo.elevationDegrees + 5.0) // bias slightly upward
            let score = p.probability * elevFactor
            if best == nil || score > best!.score {
                best = (p, score, geo)
            }
        }

        return best?.result
    }

    private func bestRelativeHeading(for result: GeoLookResult, observerHeading: Double) -> Double {
        // Relative angle to rotate UI arrow so it points on-screen: az - heading
        let rel = result.azimuthDegrees - observerHeading
        return (rel + 360).truncatingRemainder(dividingBy: 360)
    }
}

struct AuroraCompassOverlay_Previews: PreviewProvider {
    static var previews: some View {
        AuroraCompassOverlay(auroraPoints: [AuroraPoint(longitude: -149, latitude: 64.5, probability: 80)], selectedHemisphere: .north)
            .preferredColorScheme(.dark)
            .padding()
            .background(Color.black)
    }
}
