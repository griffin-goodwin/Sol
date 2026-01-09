import Foundation
import CoreLocation
import Combine

/// Observable location + heading manager for SwiftUI
@MainActor
final class LocationHeadingManager: NSObject, ObservableObject {
    @Published var location: CLLocation?
    /// Lightweight, actor-safe heading structure to avoid sending CLHeading across threads
    struct Heading {
        let trueHeading: Double
        let magneticHeading: Double
        let headingAccuracy: Double
        let timestamp: Date
    }

    @Published var heading: Heading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1.0
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
}

extension LocationHeadingManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the status value off-thread, then dispatch only values to the main actor.
        let status = manager.authorizationStatus
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.authorizationStatus = status
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                self.manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() {
                    self.manager.startUpdatingHeading()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.location = loc
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Capture primitive values off-thread, then publish a safe Heading value on main
        let th = newHeading.trueHeading
        let mh = newHeading.magneticHeading
        let acc = newHeading.headingAccuracy
        let ts = newHeading.timestamp
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.heading = Heading(trueHeading: th, magneticHeading: mh, headingAccuracy: acc, timestamp: ts)
        }
    }
}
