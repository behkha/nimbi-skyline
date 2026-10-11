import Foundation

/// Everything around the temperature, read for one moment: what the strip under the header says
/// (only what matters now), what the grid of tiles says (everything, labelled), and whether any
/// of it is worth a `notice` (very poor air, or UV 8+ under a mostly clear sky). It never changes
/// the cloud's mood and is never `needsYou`.
public struct Conditions: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case plain, warn }

    /// One chip in the strip.
    public struct Chip: Equatable, Sendable, Identifiable {
        public var id: String
        public var text: String
        /// The small second part, e.g. "gusts 12 m/s".
        public var detail: String?
        /// The whole thing in words, for VoiceOver and the tooltip.
        public var spoken: String
        public var tone: Tone = .plain
        /// 0 (best) … 5 (worst) when the chip carries a colored dot (air).
        public var band: Int?
    }

    /// One tile in the grid.
    public struct Tile: Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var value: String
        public var meaning: String
        public var tone: Tone = .plain
        /// 0…1 for the air and UV meters.
        public var meter: Double?
    }

    public var chips: [Chip]
    public var tiles: [Tile]
    public var urgency: Urgency
    /// A short line for the island's subtitle on a dry day, e.g. "air good · UV up to 3".
    public var note: String?

    public static let strongUV = 8.0

    public init(forecast: Forecast, now: Date, timeZone: TimeZone, air: AirQuality?, scale: AirScale) {
        let steps = forecast.steps
        let start = steps.lastIndex { $0.time <= now && now < $0.end } ?? steps.firstIndex { $0.time > now }
        let ahead = start.map { Array(steps[$0...]) } ?? []
        let clock = HourlyOutlook.clock(timeZone)
        var chips: [Chip] = [], tiles: [Tile] = []
        var urgency = Urgency.none
        var note: [String] = []
        let deg = HourlyOutlook.degrees

        guard let now0 = ahead.first else {
            self.init(chips: [], tiles: [], urgency: .none, note: nil)
            return
        }
        let next3 = ahead.prefix { $0.time < now.addingTimeInterval(3 * 3600) }
        let next6 = ahead.prefix { $0.time < now.addingTimeInterval(6 * 3600) }

        // Feels like.
        if let feels = now0.apparentTemperature {
            let gap = feels - now0.temperature
            if abs(gap) >= 2 { chips.append(Chip(id: "feels", text: "Feels \(deg(feels))", spoken: "Feels like \(deg(feels))")) }
            let why = abs(gap) < 1 ? "same as air" : gap < 0 ? (now0.windSpeed ?? 0) >= 4 ? "wind chill" : "cooler"
                : (now0.humidity ?? 0) >= 60 ? "humid" : "warmer"
            tiles.append(Tile(id: "feels", label: "Feels like", value: deg(feels), meaning: why))
        }

        // Wind.
        if let wind = now0.windSpeed {
            let gust = now0.windGust
            let from = now0.windFromDirection.map { " · \(Self.compass($0))" } ?? ""
            if wind >= 5 || (gust ?? 0) >= 10 {
                chips.append(Chip(id: "wind", text: "Wind \(Int(wind.rounded()))",
                                  detail: gust.map { "gusts \(Int($0.rounded())) m/s" } ?? "m/s",
                                  spoken: "Wind \(Int(wind.rounded())) metres a second" + (gust.map { ", gusts \(Int($0.rounded()))" } ?? "")))
            }
            tiles.append(Tile(id: "wind", label: "Wind", value: "\(Int(wind.rounded())) m/s",
                              meaning: (gust.map { "gusts \(Int($0.rounded()))" } ?? "calm") + from))
        }

        // Rain chance: the likeliest hour in the next six.
        let chances = next6.compactMap { s in s.precipitationChance.map { (s, $0) } }
        // When rain is already within the hour, the headline says so; the chip would only repeat it.
        let wetSoon = ahead.prefix { $0.time < now.addingTimeInterval(3600) }.contains(where: \.isWet)
        if let (step, chance) = chances.max(by: { $0.1 < $1.1 }) {
            if chance >= 30, !wetSoon {
                let when = step.time <= now ? "now" : "at \(clock.string(from: step.time))"
                chips.append(Chip(id: "rain", text: "Rain \(Int(chance.rounded()))%", detail: when,
                                  spoken: "\(Int(chance.rounded())) percent chance of rain \(when)"))
            }
            let range = now0.precipitationMax.map { max in
                max > 0 ? String(format: "%.1f–%.1f mm", now0.precipitationMin ?? 0, max) : "dry this hour"
            } ?? "next 6 hours"
            tiles.append(Tile(id: "rain", label: "Rain chance", value: "\(Int((now0.precipitationChance ?? chance).rounded()))%",
                              meaning: chance >= 30 && step.time > now ? "\(Int(chance.rounded()))% by \(clock.string(from: step.time))" : range))
        }

        // Thunder and fog, only when they're in the picture.
        if let (step, chance) = next6.compactMap({ s in s.thunderChance.map { (s, $0) } }).max(by: { $0.1 < $1.1 }), chance >= 1 {
            if chance >= 20 {
                chips.append(Chip(id: "thunder", text: "Thunder \(Int(chance.rounded()))%",
                                  spoken: "\(Int(chance.rounded())) percent chance of thunder", tone: .warn))
            }
            tiles.append(Tile(id: "thunder", label: "Thunder", value: "\(Int(chance.rounded()))%",
                              meaning: "most at \(clock.string(from: step.time))", tone: chance >= 20 ? .warn : .plain))
        }
        if let fog = now0.fog, fog >= 1 {
            if fog >= 50 { chips.append(Chip(id: "fog", text: "Fog", spoken: "Fog")) }
            tiles.append(Tile(id: "fog", label: "Fog", value: "\(Int(fog.rounded()))%", meaning: fog >= 50 ? "thick" : "patches"))
        }

        // Air quality.
        let airNow = air?.hour(at: now)
        if let level = airNow?.index(scale) {
            let name = level.name.lowercased()
            chips.append(Chip(id: "air", text: "Air \(name)", spoken: "Air quality \(name), \(scale.title) \(Int(level.value.rounded()))",
                              tone: level.isPoor ? .warn : .plain, band: level.band))
            tiles.append(Tile(id: "air", label: "Air", value: "\(Int(level.value.rounded()))", meaning: level.name,
                              tone: level.isPoor ? .warn : .plain, meter: level.fraction))
            note.append("air \(name)")
            if level.isBad { urgency = max(urgency, .notice) }
        }

        // UV: the most it reaches before sunset (MET gives it for a clear sky).
        let sunUp = Sun.isUp(at: now, coordinate: forecast.coordinate)
        let nextEvent = Sun.next(after: now, coordinate: forecast.coordinate)
        let daylightEnd: Date = { if sunUp, case .set(let d)? = nextEvent { return d }; return now }()
        let uvHours = ahead.prefix { $0.time < max(daylightEnd, now.addingTimeInterval(1)) }.compactMap { s in s.uvClearSky.map { (s, $0) } }
        if sunUp, let (peakStep, peak) = uvHours.max(by: { $0.1 < $1.1 }) {
            let uvNow = now0.uvClearSky ?? peak
            let clear3 = next3.compactMap(\.cloudCover)
            let mostlyClear = clear3.isEmpty || clear3.reduce(0, +) / Double(clear3.count) < 50
            let strong = next3.contains { ($0.uvClearSky ?? 0) >= Self.strongUV } && mostlyClear
            if peak >= 3 {
                chips.append(Chip(id: "uv", text: "UV up to \(Int(peak.rounded()))",
                                  spoken: "UV index up to \(Int(peak.rounded())) at \(clock.string(from: peakStep.time)) under a clear sky",
                                  tone: strong ? .warn : .plain))
                note.append("UV up to \(Int(peak.rounded()))")
            }
            tiles.append(Tile(id: "uv", label: "UV", value: "\(Int(uvNow.rounded()))",
                              meaning: "peak \(Int(peak.rounded())) at \(clock.string(from: peakStep.time))",
                              tone: strong ? .warn : .plain, meter: min(1, peak / 11)))
            if strong { urgency = max(urgency, .notice) }
        }

        // Pollen, in Europe.
        if let strongest = airNow?.strongestPollen {
            if strongest.level >= .moderate {
                chips.append(Chip(id: "pollen", text: "\(strongest.kind.name) pollen \(strongest.level.name)",
                                  spoken: "\(strongest.kind.name) pollen \(strongest.level.name)",
                                  tone: strongest.level >= .high ? .warn : .plain))
            }
            tiles.append(Tile(id: "pollen", label: "Pollen", value: strongest.level.name.prefix(1).uppercased() + strongest.level.name.dropFirst(),
                              meaning: strongest.kind.name.lowercased(), tone: strongest.level >= .high ? .warn : .plain))
        } else if air?.hasPollen == true {
            tiles.append(Tile(id: "pollen", label: "Pollen", value: "None", meaning: "nothing in the air"))
        }

        // Sun: the next sunrise or sunset.
        switch nextEvent {
        case .set(let d)?:
            chips.append(Chip(id: "sun", text: "Sunset \(clock.string(from: d))", spoken: "Sunset at \(clock.string(from: d))"))
            let left = Int(d.timeIntervalSince(now) / 60)
            tiles.append(Tile(id: "sun", label: "Sunset", value: clock.string(from: d),
                              meaning: left >= 60 ? "\(left / 60) h \(left % 60) m left" : "\(left) min left"))
        case .rise(let d)?:
            chips.append(Chip(id: "sun", text: "Sunrise \(clock.string(from: d))", spoken: "Sunrise at \(clock.string(from: d))"))
            tiles.append(Tile(id: "sun", label: "Sunrise", value: clock.string(from: d), meaning: "sun is down"))
        case nil:
            tiles.append(Tile(id: "sun", label: "Sun", value: sunUp ? "Up" : "Down", meaning: sunUp ? "all day" : "all night"))
        }

        // Humidity, pressure and clouds: grid only.
        if let humidity = now0.humidity {
            tiles.append(Tile(id: "humidity", label: "Humidity", value: "\(Int(humidity.rounded()))%",
                              meaning: now0.dewPoint.map { "dew point \(deg($0))" } ?? ""))
        }
        if let pressure = now0.pressure {
            let later = ahead.first { $0.time >= now.addingTimeInterval(3 * 3600) }?.pressure
            let trend = later.map { $0 - pressure > 1 ? "rising" : pressure - $0 > 1 ? "falling" : "steady" } ?? ""
            tiles.append(Tile(id: "pressure", label: "Pressure", value: "\(Int(pressure.rounded()))", meaning: "hPa · \(trend)"))
        }
        if let cover = now0.cloudCover {
            let layers = [("low", now0.cloudLow), ("mid", now0.cloudMedium), ("high", now0.cloudHigh)]
                .compactMap { name, v in v.map { (name, $0) } }
            let main = layers.max { $0.1 < $1.1 }
            tiles.append(Tile(id: "clouds", label: "Clouds", value: "\(Int(cover.rounded()))%",
                              meaning: cover < 5 ? "clear" : main.map { "mostly \($0.0)" } ?? ""))
        }

        self.init(chips: chips, tiles: tiles, urgency: urgency, note: note.isEmpty ? nil : note.joined(separator: " · "))
    }

    public init(chips: [Chip], tiles: [Tile], urgency: Urgency, note: String?) {
        self.chips = chips
        self.tiles = tiles
        self.urgency = urgency
        self.note = note
    }

    static func compass(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[i]
    }
}
