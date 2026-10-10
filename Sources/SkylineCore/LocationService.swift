import CoreLocation
import Foundation

/// A place to forecast: where the Mac is, or a city the user picked.
public struct Place: Codable, Equatable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    /// IANA identifier, for local days and hours. `nil` means the Mac's own time zone.
    public var timeZoneID: String?

    public init(name: String, coordinate: Coordinate, timeZoneID: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.timeZoneID = timeZoneID
    }

    public var timeZone: TimeZone { timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
}

/// Where Skyline forecasts for. Uses Location Services when allowed, a city the user picked
/// otherwise (or always, if they chose one). Reports a new place only after a real move of
/// `moveThreshold`, so GPS jitter never turns into new MET requests.
@MainActor
public final class LocationService: NSObject, ObservableObject {
    public enum Mode: String, Codable, Sendable { case automatic, manual }

    public enum Status: Equatable, Sendable {
        case locating
        case ready
        /// Location Services is off or denied for Skyline, and no city is set yet.
        case needsCity
    }

    @Published public private(set) var place: Place?
    @Published public private(set) var status: Status = .locating
    @Published public private(set) var mode: Mode

    public static let moveThreshold: CLLocationDistance = 1_000

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let defaults: UserDefaults
    private var manualPlace: Place?

    private enum Key {
        static let mode = "LocationMode"
        static let manualPlace = "ManualPlace"
        static let lastPlace = "LastPlace"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Key.mode).flatMap(Mode.init(rawValue:)) ?? .automatic
        manualPlace = Self.decode(defaults.data(forKey: Key.manualPlace))
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = Self.moveThreshold
        // Show the last known place at once; a fresh fix replaces it.
        place = mode == .manual ? manualPlace : Self.decode(defaults.data(forKey: Key.lastPlace))
    }

    public func start() {
        switch mode {
        case .manual:
            manager.stopUpdatingLocation()
            status = manualPlace == nil ? .needsCity : .ready
            place = manualPlace
        case .automatic:
            applyAuthorization(manager.authorizationStatus)
        }
    }

    /// Pick a city. Switches to manual mode.
    public func choose(_ place: Place) {
        manualPlace = place
        defaults.set(Self.encode(place), forKey: Key.manualPlace)
        setMode(.manual)
    }

    public func setMode(_ newMode: Mode) {
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Key.mode)
        start()
    }

    /// Cities matching `query`, for the place picker.
    public func search(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if geocoder.isGeocoding { geocoder.cancelGeocode() }
        let placemarks = try await geocoder.geocodeAddressString(trimmed)
        return placemarks.compactMap(Self.place(from:))
    }

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self.status = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            if let manualPlace {
                place = manualPlace
                self.status = .ready
            } else {
                self.status = .needsCity
            }
        default:
            self.status = place == nil ? .locating : .ready
            manager.startUpdatingLocation()
        }
    }

    private func received(_ location: CLLocation) {
        guard mode == .automatic else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if let place, place.coordinate.distance(to: coordinate) < Self.moveThreshold, status == .ready { return }
        let provisional = Place(name: place?.name ?? "Here", coordinate: coordinate, timeZoneID: place?.timeZoneID)
        publish(provisional)
        Task { [weak self] in
            guard let self else { return }
            let named = try? await self.geocoder.reverseGeocodeLocation(location).first.flatMap(Self.place(from:))
            guard self.mode == .automatic, let named else { return }
            self.publish(Place(name: named.name, coordinate: coordinate, timeZoneID: named.timeZoneID))
        }
    }

    private func publish(_ newPlace: Place) {
        place = newPlace
        status = .ready
        defaults.set(Self.encode(newPlace), forKey: Key.lastPlace)
    }

    nonisolated static func place(from placemark: CLPlacemark) -> Place? {
        guard let location = placemark.location else { return nil }
        let name = placemark.locality ?? placemark.name ?? placemark.administrativeArea ?? placemark.country ?? "Here"
        return Place(name: name,
                     coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                     timeZoneID: placemark.timeZone?.identifier)
    }

    private static func encode(_ place: Place) -> Data? { try? JSONEncoder().encode(place) }
    private static func decode(_ data: Data?) -> Place? { data.flatMap { try? JSONDecoder().decode(Place.self, from: $0) } }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.mode == .automatic else { return }
            self.applyAuthorization(status)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.received(location) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.place == nil { self.status = self.manualPlace == nil ? .needsCity : .ready }
            if self.place == nil { self.place = self.manualPlace }
        }
    }
}
