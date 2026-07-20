import CoreLocation
import Combine
import Foundation

enum RoutePlanningOriginState: Equatable {
    case awaitingOrigin
    case locating
    case resolved(String)
    case manualEntry(message: String?)

}

@MainActor
final class RoutePlanningLocationCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: RoutePlanningOriginState = .awaitingOrigin

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    func useCurrentLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            useManualEntry(message: "Location Services is unavailable. Enter a starting address instead.")
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            state = .locating
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            state = .locating
            locationManager.requestLocation()
        case .denied, .restricted:
            useManualEntry(message: "Location access is off. Enter a starting address instead.")
        @unknown default:
            useManualEntry(message: "We couldn't access your location. Enter a starting address instead.")
        }
    }

    func useManualEntry(message: String? = nil) {
        locationManager.stopUpdatingLocation()
        state = .manualEntry(message: message)
    }

    private func resolve(_ location: CLLocation) async {
        do {
            let placemark = try await geocoder.reverseGeocodeLocation(location).first
            guard let address = Self.address(from: placemark) else {
                useManualEntry(message: "We couldn't turn that location into an address. Enter one instead.")
                return
            }
            state = .resolved(address)
        } catch {
            useManualEntry(message: "We couldn't confirm your address. Enter it manually instead.")
        }
    }

    static func address(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let locality = [placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let parts = [street, locality, placemark.country ?? ""].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension RoutePlanningLocationCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, case .locating = self.state else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.useManualEntry(message: "Location access is off. Enter a starting address instead.")
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 150 else { return }
        manager.stopUpdatingLocation()
        Task { @MainActor [weak self] in
            await self?.resolve(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.useManualEntry(message: "We couldn't get a current location. Enter a starting address instead.")
        }
    }
}
