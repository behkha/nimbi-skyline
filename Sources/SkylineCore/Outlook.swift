import Foundation

/// The next hours as the dropdown's chart draws them, and the sentence VoiceOver reads instead.
public struct HourlyOutlook: Equatable, Sendable {
    public struct Hour: Equatable, Sendable {
        public var time: Date
        /// °C at `time`.
        public var temperature: Double
        /// mm over the hour that starts at `time`.
        public var precipitation: Double
        /// MET's 10–90% temperature range, when the response has it.
        public var temperatureLow: Double? = nil
        public var temperatureHigh: Double? = nil
        /// % chance of rain over the hour.
        public var chance: Double? = nil
    }

    public var hours: [Hour]

    /// Up to `count` hourly steps from the one covering `now`. Six-hourly steps further out are
    /// left off: a bar for six hours would not compare with the hourly ones.
    public init(forecast: Forecast, now: Date, count: Int = 24) {
        let steps = forecast.steps
        let start = steps.lastIndex(where: { $0.time <= now && now < $0.end })
            ?? steps.firstIndex(where: { $0.time > now }) ?? steps.endIndex
        hours = steps[start...].prefix { $0.period <= 3600 }.prefix(count).map {
            Hour(time: $0.time, temperature: $0.temperature, precipitation: $0.precipitation ?? 0,
                 temperatureLow: $0.temperatureLow, temperatureHigh: $0.temperatureHigh, chance: $0.precipitationChance)
        }
    }

    public init(hours: [Hour]) { self.hours = hours }

    public var coldest: Hour? { hours.min { $0.temperature < $1.temperature } }
    public var warmest: Hour? { hours.max { $0.temperature < $1.temperature } }
    /// The wettest hour, if any hour has 0.1 mm or more.
    public var wettest: Hour? { hours.filter { $0.precipitation >= 0.1 }.max { $0.precipitation < $1.precipitation } }

    /// What the chart shows, in one sentence: for VoiceOver and the chart's tooltip.
    public func summary(timeZone: TimeZone) -> String {
        guard let first = hours.first, let coldest, let warmest else { return "No hourly forecast yet." }
        let clock = Self.clock(timeZone)
        var parts = ["Next \(hours.count) hours: \(Self.degrees(first.temperature)) now"]
        if warmest.time != first.time { parts.append("high \(Self.degrees(warmest.temperature)) at \(clock.string(from: warmest.time))") }
        if coldest.time != first.time { parts.append("low \(Self.degrees(coldest.temperature)) at \(clock.string(from: coldest.time))") }
        var text = parts.joined(separator: ", ") + "."
        let wet = hours.filter { $0.precipitation >= 0.1 }
        if let start = wet.first, let end = wet.last, let wettest {
            let until = clock.string(from: end.time.addingTimeInterval(3600))
            let total = wet.reduce(0) { $0 + $1.precipitation }
            text += " Rain \(clock.string(from: start.time))–\(until), \(Self.millimetres(total)) in all,"
                + " heaviest \(Self.millimetres(wettest.precipitation)) at \(clock.string(from: wettest.time))."
        } else {
            text += " No rain."
        }
        return text
    }

    static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
    static func millimetres(_ value: Double) -> String { String(format: "%.1f mm", value) }

    static func clock(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f
    }
}

extension WeatherSymbol {
    /// MET's code in words: "lightrainshowersandthunder" reads "Light rain showers and thunder".
    public var phrase: String {
        let words = ["partly", "cloudy", "clear", "sky", "fair", "fog", "light", "heavy",
                     "rain", "sleet", "snow", "showers", "and", "thunder"]
        var rest = Substring(base)
        var found: [String] = []
        while !rest.isEmpty {
            guard let word = words.first(where: { rest.hasPrefix($0) }) else { return base }
            found.append(word)
            rest = rest.dropFirst(word.count)
        }
        let text = found.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

extension SkyReport {
    /// The line under the place name: the most important thing about the sky right now, in the
    /// order the cloud's mood weighs it (hazards, then rain, then the plain condition).
    public func headline(timeZone: TimeZone) -> String {
        let clock = HourlyOutlook.clock(timeZone)
        if let hazard = hazards.first {
            switch hazard {
            case .thunder(let at): return "Thunder from \(clock.string(from: at))"
            case .storm(let at, _): return "Storm-force wind from \(clock.string(from: at))"
            case .heat(let at, let t): return "Dangerous heat, \(HourlyOutlook.degrees(t)) by \(clock.string(from: at))"
            }
        }
        let condition = current.symbol?.phrase ?? "No word on the sky"
        switch rain {
        case .soon: return "Rain within the hour"
        case .now(let until, _):
            let wet = current.symbol?.isPrecipitation == true ? condition : "Rain"
            return "\(wet) until \(clock.string(from: until))"
        case .later(let at, _): return "\(condition) · rain from \(clock.string(from: at))"
        case .dry: return condition
        }
    }
}
