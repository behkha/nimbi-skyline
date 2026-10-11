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

    public enum Event: Equatable, Sendable {
        case rise(Date)
        case set(Date)

        public var date: Date {
            switch self { case .rise(let d), .set(let d): return d }
        }
    }

    /// Sunrises and sunsets between two moments, in order, each to within a few seconds.
    /// Empty on a polar day or night.
    public static func events(from start: Date, to end: Date, coordinate: Coordinate) -> [Event] {
        let step: TimeInterval = 10 * 60
        var found: [Event] = []
        var t = start
        var wasUp = isUp(at: t, coordinate: coordinate)
        while t < end {
            let next = min(end, t.addingTimeInterval(step))
            let up = isUp(at: next, coordinate: coordinate)
            if up != wasUp {
                // Halve the ten minutes down to about a second.
                var lo = t, hi = next
                for _ in 0..<10 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    if isUp(at: mid, coordinate: coordinate) == wasUp { lo = mid } else { hi = mid }
                }
                found.append(up ? .rise(hi) : .set(hi))
            }
            wasUp = up
            t = next
        }
        return found
    }

    /// Sunrise and sunset on the local day that contains `date`; nil where the sun doesn't
    /// rise or set that day.
    public static func times(on date: Date, coordinate: Coordinate, timeZone: TimeZone) -> (rise: Date?, set: Date?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return (nil, nil) }
        let all = events(from: start, to: end, coordinate: coordinate)
        let rise = all.first { if case .rise = $0 { return true }; return false }
        let set = all.first { if case .set = $0 { return true }; return false }
        return (rise?.date, set?.date)
    }

    /// The next sunrise or sunset within two days.
    public static func next(after date: Date, coordinate: Coordinate) -> Event? {
        events(from: date, to: date.addingTimeInterval(2 * 86_400), coordinate: coordinate).first
    }

    private static func normalize(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}
