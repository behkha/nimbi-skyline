import Foundation

/// Where the sun is, computed locally so Skyline needs no second API for day and night.
/// Low-precision solar position (Astronomical Almanac), good to about 0.1° until 2050.
public enum Sun {
    /// Sun center at -0.833°: the standard sunrise/sunset line (refraction plus the sun's radius).
    public static let horizon = -0.833

    /// Elevation above the horizon in degrees.
    public static func elevation(at date: Date, coordinate: Coordinate) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
        let meanLongitude = normalize(280.460 + 0.985_647_4 * n)
        let anomaly = normalize(357.528 + 0.985_600_3 * n) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let obliquity = (23.439 - 0.000_000_4 * n) * rad

        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let siderealHours = (18.697_374_558 + 24.065_709_824_419_08 * n).truncatingRemainder(dividingBy: 24)
        let hourAngle = (siderealHours * 15 + coordinate.longitude) * rad - rightAscension
        let latitude = coordinate.latitude * rad

        let s = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
        return asin(max(-1, min(1, s))) / rad
    }

    public static func isUp(at date: Date, coordinate: Coordinate) -> Bool {
        elevation(at: date, coordinate: coordinate) > horizon
    }

    private static func normalize(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}
