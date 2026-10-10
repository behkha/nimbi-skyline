import Foundation

/// What the forecast means right now: the facts the menu bar, the dropdown and the cloud's mood
/// are built from. Pure: the same forecast and moment always give the same report.
public struct SkyReport: Equatable, Sendable {
    public enum Rain: Equatable, Sendable {
        /// Nothing wet within `SkyReport.rainHorizon`.
        case dry
        /// Wet now, until `until` (the end of the wet run), heaviest at `peak` mm/h.
        case now(until: Date, peak: Double)
        /// Starts within the hour. Steps are hourly, so this means "within the hour", never "in 12 min".
        case soon(at: Date, peak: Double)
        /// Starts later within the horizon.
        case later(at: Date, peak: Double)

        public var isWetNow: Bool { if case .now = self { return true }; return false }
        public var isSoon: Bool { if case .soon = self { return true }; return false }
    }

    public enum Hazard: Equatable, Sendable {
        case thunder(at: Date)
        /// Mean wind of at least storm force (Beaufort 9, 20.8 m/s).
        case storm(at: Date, windSpeed: Double)
        case heat(at: Date, temperature: Double)
    }

    public struct Day: Equatable, Sendable {
        /// Midnight, local time.
        public var date: Date
        public var low: Double
        public var high: Double
        /// mm over the part of the day the forecast covers.
        public var precipitation: Double
        /// The most notable weather of the daytime hours.
        public var symbol: WeatherSymbol?
    }

    public var current: ForecastStep
    public var rain: Rain
    /// Within the next `hazardHorizon`, soonest first.
    public var hazards: [Hazard]
    /// Up to five days, today first.
    public var days: [Day]
    public var isNight: Bool

    public static let rainSoon: TimeInterval = 60 * 60
    public static let rainHorizon: TimeInterval = 12 * 60 * 60
    public static let hazardHorizon: TimeInterval = 3 * 60 * 60
    public static let stormWind = 20.8
    public static let dangerousHeat = 35.0
    public static let hot = 30.0

    public var isHot: Bool { current.temperature >= Self.hot }

    /// `nil` when the forecast has nothing at or after `now`.
    public init?(forecast: Forecast, now: Date, timeZone: TimeZone = .current, dayCount: Int = 5) {
        let steps = forecast.steps
        // The step whose period covers now, else the first one ahead of it.
        guard let index = steps.lastIndex(where: { $0.time <= now && now < $0.end })
                ?? steps.firstIndex(where: { $0.time > now }) else { return nil }
        let ahead = Array(steps[index...])
        current = ahead[0]
        rain = Self.rain(in: ahead, now: now)
        hazards = Self.hazards(in: ahead, now: now)
        days = Self.days(from: steps, now: now, timeZone: timeZone, count: dayCount)
        isNight = !Sun.isUp(at: now, coordinate: forecast.coordinate)
    }

    static func rain(in steps: [ForecastStep], now: Date) -> Rain {
        let horizon = now.addingTimeInterval(rainHorizon)
        guard let first = steps.firstIndex(where: { $0.isWet && $0.time < horizon }) else { return .dry }
        var last = first
        while last + 1 < steps.count, steps[last + 1].isWet, steps[last + 1].time == steps[last].end { last += 1 }
        let peak = steps[first...last].map(\.precipitationRate).max() ?? 0
        let start = steps[first].time
        if start <= now { return .now(until: steps[last].end, peak: peak) }
        if start.timeIntervalSince(now) <= rainSoon { return .soon(at: start, peak: peak) }
        return .later(at: start, peak: peak)
    }

    static func hazards(in steps: [ForecastStep], now: Date) -> [Hazard] {
        let horizon = now.addingTimeInterval(hazardHorizon)
        var found: [Hazard] = []
        for step in steps where step.time < horizon {
            let at = max(step.time, now)
            if step.symbol?.isThunder == true, !found.contains(where: { if case .thunder = $0 { return true }; return false }) {
                found.append(.thunder(at: at))
            }
            if let wind = step.windSpeed, wind >= stormWind,
               !found.contains(where: { if case .storm = $0 { return true }; return false }) {
                found.append(.storm(at: at, windSpeed: wind))
            }
            if step.temperature >= dangerousHeat,
               !found.contains(where: { if case .heat = $0 { return true }; return false }) {
                found.append(.heat(at: at, temperature: step.temperature))
            }
        }
        return found
    }

    static func days(from steps: [ForecastStep], now: Date, timeZone: TimeZone, count: Int) -> [Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        var result: [Day] = []
        for offset in 0..<count {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { break }
            // Today counts only what's still ahead; later days count everything in them.
            let inDay = steps.filter { $0.time >= start && $0.time < end && $0.end > now }
            guard !inDay.isEmpty else { break }
            let temps = inDay.map(\.temperature)
            let precipitation = inDay.reduce(0) { total, step in
                // A six-hour period that runs past midnight is shared by overlap.
                let overlap = min(step.end, end).timeIntervalSince(max(step.time, start))
                return total + (step.precipitation ?? 0) * max(0, overlap) / step.period
            }
            let daytime = inDay.filter {
                let hour = calendar.component(.hour, from: $0.time)
                return hour >= 6 && hour < 20
            }
            let symbol = (daytime.isEmpty ? inDay : daytime).compactMap(\.symbol).max { $0.severity < $1.severity }
            result.append(Day(date: start, low: temps.min()!, high: temps.max()!,
                              precipitation: (precipitation * 10).rounded() / 10, symbol: symbol))
        }
        return result
    }
}
