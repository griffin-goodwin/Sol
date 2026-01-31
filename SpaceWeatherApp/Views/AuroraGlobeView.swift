import SwiftUI
import MapKit
import CoreLocation

// MARK: - User Location Annotation

class UserLocationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String? = "You"

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

// MARK: - Custom Overlay for Aurora Data

/// Custom overlay that holds aurora point data
class AuroraOverlay: NSObject, MKOverlay {
    let points: [AuroraPoint]
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    
    init(points: [AuroraPoint]) {
        self.points = points
        
        // Calculate bounding box for all points
        if points.isEmpty {
            self.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
            self.boundingMapRect = MKMapRect.world
        } else {
            var minLat = 90.0
            var maxLat = -90.0
            var minLon = 180.0
            var maxLon = -180.0
            
            for point in points {
                minLat = min(minLat, point.latitude)
                maxLat = max(maxLat, point.latitude)
                minLon = min(minLon, point.longitude)
                maxLon = max(maxLon, point.longitude)
            }
            
            self.coordinate = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            
            let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
            let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
            
            self.boundingMapRect = MKMapRect(
                x: topLeft.x,
                y: topLeft.y,
                width: bottomRight.x - topLeft.x,
                height: bottomRight.y - topLeft.y
            )
        }
        
        super.init()
    }
}

// MARK: - Custom Renderer for Aurora Overlay

class AuroraOverlayRenderer: MKOverlayRenderer {
    private let auroraOverlay: AuroraOverlay
    
    init(overlay: AuroraOverlay) {
        self.auroraOverlay = overlay
        super.init(overlay: overlay)
        
        // Enable alpha blending
        self.alpha = 1.0
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.saveGState()
        
        var drawnCount = 0
        var totalRadiusPoints: Double = 0
        
        for (idx, point) in auroraOverlay.points.enumerated() {
            let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            let mapPoint = MKMapPoint(coordinate)
            
            // Calculate radius in METERS
            let radiusMeters = auroraBandRadius(for: point.probability)
            
            // Convert to MKMapPoints using the proper scale at this latitude
            let metersPerMapPoint = MKMetersPerMapPointAtLatitude(coordinate.latitude)
            let radiusInMapPoints = radiusMeters / metersPerMapPoint
            
            // Convert from map points to screen points using MKMapPointsPerPoint
            // This is the KEY fix - we need to account for the contentScaleFactor
            let radiusScreenPoints = CGFloat(radiusInMapPoints / MKMapPointsPerPoint(at: zoomScale))
            
            totalRadiusPoints += radiusScreenPoints
            
            // Skip if radius is too small to see (lowered threshold)
            guard radiusScreenPoints > 0.5 else { continue }
            
            // Get color with baked-in alpha (shared helper)
            let color = auroraCGColor(for: point.probability)
            
            // Build an MKMapRect around the point and convert to renderer coordinates
            let pointMapRect = MKMapRect(x: mapPoint.x - radiusInMapPoints, y: mapPoint.y - radiusInMapPoints, width: radiusInMapPoints * 2.0, height: radiusInMapPoints * 2.0)
            let circleRect = self.rect(for: pointMapRect)
            
            // Ensure antialiasing and normal blend for clear rendering
            context.setAllowsAntialiasing(true)
            context.setBlendMode(.normal)

            // If color is very faint, boost alpha for visibility while debugging
            var drawColor = color
            if color.alpha < 0.25 {
                if let boosted = color.copy(alpha: min(1.0, color.alpha * 4.0)) {
                    drawColor = boosted
                }
            }

            // Fill with (possibly boosted) color
            context.setFillColor(drawColor)
            context.fillEllipse(in: circleRect)

            // Add a bright stroke for visibility
            context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1.0))
            context.setLineWidth(2.0)
            context.strokeEllipse(in: circleRect)
            
            drawnCount += 1
        }
        
        context.restoreGState()
        
        if drawnCount > 0 {
            let _ = totalRadiusPoints / Double(drawnCount)
        }
    }
    
    // Helper to convert zoom scale properly
    private func MKMapPointsPerPoint(at zoomScale: MKZoomScale) -> Double {
        return 1.0 / Double(zoomScale)
    }
    
    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        return true
    }
    
    // MARK: - Helper Functions (same as before)
    
    private func auroraBandRadius(for probability: Double) -> CLLocationDistance {
        return 60_000 + (probability / 100.0) * 50_000
    }
    
    // Color gradient and lerp helpers moved to Utilities/AuroraColors.swift
}

// MARK: - SwiftUI Map View with Overlay

@available(iOS 17.0, *)
struct AuroraMapGlobeView: View {
    let auroraPoints: [AuroraPoint]
    let hemisphere: Hemisphere
    let maxCircles: Int

    @State private var position: MapCameraPosition
    @State private var cachedPoints: CachedAuroraPoints?
    @State private var isProcessing = false
    @State private var preprocessTask: Task<CachedAuroraPoints?, Never>? = nil
    @State private var useGlobe = true
    @StateObject private var locationManager = LocationHeadingManager()

    init(auroraPoints: [AuroraPoint], hemisphere: Hemisphere, maxCircles: Int = 1000) {
        self.auroraPoints = auroraPoints
        self.hemisphere = hemisphere
        self.maxCircles = maxCircles

        let centerLat = hemisphere == .north ? 65.0 : -65.0
        _position = State(initialValue: .camera(
            MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: 0),
                distance: 18_000_000,
                heading: 0,
                pitch: 0
            )
        ))
    }
    
    var body: some View {
        ZStack {
            // Use UIViewRepresentable to access MKMapView directly
            AuroraMapViewRepresentable(
                points: currentHemispherePoints,
                position: $position,
                hemisphere: hemisphere,
                useGlobe: useGlobe,
                userLocation: locationManager.location
            )
            .opacity(isProcessing ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isProcessing)
            
            // Info badge
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aurora Points")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.tertiaryText)
                        Text("\(currentHemispherePoints.count)")
                            .font(Theme.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.auroraGreen)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Compact icon-only globe/map toggle
                    Button(action: { withAnimation { useGlobe.toggle() } }) {
                        Image(systemName: useGlobe ? "globe" : "map")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()
                }
                .padding(Theme.Spacing.md)

                Spacer()
            }
            
            if isProcessing {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    
                    Text("Processing aurora data...")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 10)
            }
        }
        .task(id: auroraPoints.count) {
            await preprocessData()
        }
        .onChange(of: maxCircles) { _, newValue in
            Task {
                await preprocessData()
            }
        }
        .onDisappear {
            cleanupOnDisappear()
        }
    }
    
    private var currentHemispherePoints: [AuroraPoint] {
        guard let cache = cachedPoints else { return [] }
        
        let points = hemisphere == .north ? cache.northernPoints : cache.southernPoints
        
        return points
    }
    
    private func preprocessData() async {
        guard !isProcessing else { return }
        
        preprocessTask?.cancel()
        
        await MainActor.run {
            isProcessing = true
        }
        
        let targetPerHemisphere = max(1, self.maxCircles)
        
        let task = Task.detached(priority: .userInitiated) { () -> CachedAuroraPoints? in
            let cache = CachedAuroraPoints(points: auroraPoints, targetPointsPerHemisphere: targetPerHemisphere)
            return Task.isCancelled ? nil : cache
        }
        
        preprocessTask = task
        let cache = await task.value
        
        guard let cache else {
            await MainActor.run {
                self.isProcessing = false
            }
            preprocessTask = nil
            return
        }
        
        await MainActor.run {
            self.cachedPoints = cache
            self.isProcessing = false
        }
        
        preprocessTask = nil
    }
    
    private func cleanupOnDisappear() {
        preprocessTask?.cancel()
        preprocessTask = nil
        cachedPoints = nil
        isProcessing = false
    }
}

// MARK: - UIViewRepresentable for MKMapView

@available(iOS 17.0, *)
struct AuroraMapViewRepresentable: UIViewRepresentable {
    let points: [AuroraPoint]
    @Binding var position: MapCameraPosition
    let hemisphere: Hemisphere
    let useGlobe: Bool
    let userLocation: CLLocation?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        // Set based on selection
        mapView.mapType = useGlobe ? .satelliteFlyover : .standard
        mapView.delegate = context.coordinator

        // Set initial camera
        let centerLat = hemisphere == .north ? 65.0 : -65.0
        let camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: centerLat, longitude: 0),
            fromDistance: 18_000_000,
            pitch: 0,
            heading: 0
        )
        mapView.setCamera(camera, animated: false)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Ensure selected style
        mapView.mapType = useGlobe ? .satelliteFlyover : .standard

        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        // Add new overlay with current points
        if !points.isEmpty {
            let overlay = AuroraOverlay(points: points)
            // Use aboveLabels to ensure overlay renders on top of map content for visibility
            mapView.addOverlay(overlay, level: .aboveLabels)

            // Force a redraw and request renderer to update (helps with z-order issues)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                mapView.setNeedsDisplay()
                if let renderer = mapView.renderer(for: overlay) {
                    renderer.setNeedsDisplay()
                }
            }
        }

        // Add user location annotation
        if let location = userLocation {
            let annotation = UserLocationAnnotation(coordinate: location.coordinate)
            mapView.addAnnotation(annotation)
        }

        // Update camera when hemisphere changes
        context.coordinator.updateCamera(mapView: mapView, hemisphere: hemisphere, position: position)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(hemisphere: hemisphere)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var currentHemisphere: Hemisphere
        
        init(hemisphere: Hemisphere) {
            self.currentHemisphere = hemisphere
        }
        
        func updateCamera(mapView: MKMapView, hemisphere: Hemisphere, position: MapCameraPosition) {
            guard hemisphere != currentHemisphere else { return }
            currentHemisphere = hemisphere
            
            let centerLat = hemisphere == .north ? 65.0 : -65.0
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: centerLat, longitude: 0),
                fromDistance: 18_000_000,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: true)
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let auroraOverlay = overlay as? AuroraOverlay {
                return AuroraOverlayRenderer(overlay: auroraOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Don't override the built-in user location
            if annotation is MKUserLocation {
                return nil
            }

            // Custom view for our user location annotation
            if annotation is UserLocationAnnotation {
                let identifier = "UserLocation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true

                    // Create a custom view for the user location
                    let size: CGFloat = 24
                    let containerView = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))

                    // Outer glow circle
                    let glowCircle = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                    glowCircle.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
                    glowCircle.layer.cornerRadius = size / 2
                    containerView.addSubview(glowCircle)

                    // Inner circle
                    let innerSize: CGFloat = 14
                    let innerCircle = UIView(frame: CGRect(x: (size - innerSize) / 2, y: (size - innerSize) / 2, width: innerSize, height: innerSize))
                    innerCircle.backgroundColor = .systemBlue
                    innerCircle.layer.cornerRadius = innerSize / 2
                    innerCircle.layer.borderWidth = 2
                    innerCircle.layer.borderColor = UIColor.white.cgColor
                    containerView.addSubview(innerCircle)

                    // Render the view to an image
                    let renderer = UIGraphicsImageRenderer(size: containerView.bounds.size)
                    let image = renderer.image { context in
                        containerView.layer.render(in: context.cgContext)
                    }

                    annotationView?.image = image
                    annotationView?.centerOffset = CGPoint(x: 0, y: 0)
                } else {
                    annotationView?.annotation = annotation
                }

                return annotationView
            }

            return nil
        }
    }
}

// MARK: - Cached Aurora Points (same as before)

struct CachedAuroraPoints: Sendable {
    let northernPoints: [AuroraPoint]
    let southernPoints: [AuroraPoint]
    
    init(points: [AuroraPoint], targetPointsPerHemisphere: Int = 1000) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let validPoints = points.filter { point in
            abs(abs(point.latitude) - 90.0) >= 0.01
        }
        
        let northRaw = validPoints.filter { $0.latitude > 0 }
        let southRaw = validPoints.filter { $0.latitude < 0 }
        
        self.northernPoints = Self.samplePoints(northRaw, targetCount: targetPointsPerHemisphere)
        self.southernPoints = Self.samplePoints(southRaw, targetCount: targetPointsPerHemisphere)
        
        let _ = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    }
    
    private static func samplePoints(_ points: [AuroraPoint], targetCount: Int, minProbability: Double = 3.0) -> [AuroraPoint] {
        let filtered = points.filter { $0.probability >= minProbability }
        
        let _ = (points.count, filtered.count, targetCount)
        
        guard filtered.count > targetCount else { 
            // using all filtered points (below target)
            return filtered 
        }
        
        // Optimized grid-based sampling
        let latBandSize = 2.5
        let lonBandSize = 6.0
        
        var grid: [Int: [Int: [AuroraPoint]]] = [:]
        
        for point in filtered {
            let latBand = Int(floor(point.latitude / latBandSize))
            let lonBand = Int(floor(point.longitude / lonBandSize))
            grid[latBand, default: [:]][lonBand, default: []].append(point)
        }
        
        let totalCells = grid.values.reduce(0) { $0 + $1.count }
        let pointsPerCell = max(1, targetCount / totalCells)
        
        let _ = (totalCells, pointsPerCell)
        
        var sampled: [AuroraPoint] = []
        sampled.reserveCapacity(targetCount)
        
        for (_, lonBands) in grid {
            for (_, cellPoints) in lonBands {
                let sortedByProb = cellPoints.sorted { $0.probability > $1.probability }
                sampled.append(contentsOf: sortedByProb.prefix(pointsPerCell))
            }
        }
        
        // Final trim if needed
        if sampled.count > targetCount {
            // trimming sampled array to target count
            sampled = Array(sampled.sorted { $0.probability > $1.probability }.prefix(targetCount))
        }
        
        let _ = sampled.count
        return sampled
    }
}