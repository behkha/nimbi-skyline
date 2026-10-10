import Foundation

/// A point on Earth in degrees. Requests to MET carry at most four decimals (about 11 m), as its
/// terms require; anything finer is truncated, never rounded up past the user's real position.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    /// Truncated toward zero to `decimals` places.
    public func truncated(to decimals: Int = 4) -> Coordinate {
        let scale = pow(10, Double(decimals))
        return Coordinate(latitude: (latitude * scale).rounded(.towardZero) / scale,
                          longitude: (longitude * scale).rounded(.towardZero) / scale)
    }

    /// "59.9139" style text for query strings and cache keys; no trailing zeros, no exponent.
    static func format(_ value: Double, decimals: Int = 4) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// Stable file-name-safe key for the forecast cache.
    public var cacheKey: String {
        let t = truncated()
        return "\(Coordinate.format(t.latitude))_\(Coordinate.format(t.longitude))"
    }

    /// Great-circle distance in meters (haversine).
    public func distance(to other: Coordinate) -> Double {
        let r = 6_371_000.0
        let p1 = latitude * .pi / 180, p2 = other.latitude * .pi / 180
        let dp = p2 - p1, dl = (other.longitude - longitude) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}
