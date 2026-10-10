import Foundation

/// Skyline's page for the notch island, in DESIGN.md 18.4's page format (option A in
/// docs/design-choices.md): a glance for the closed island, a title and subtitle, and twelve
/// bars, rain for the next 12 hours or the temperature on a dry day.
public struct IslandPage: Equatable, Sendable {
    public enum Bars: Equatable, Sendable {
        /// mm in each of the next hours.
        case rain([Double])
        /// °C at each of the next hours.
        case temperature([Double])
    }

    /// At most 14 characters: "☂︎ 18°" when rain is coming, else "18°".
    public var glance: String
    /// At most 28 characters, like "18° · rain within the hour".
    public var title: String
    /// At most 60 characters.
    public var subtitle: String
    public var bars: Bars
    public var urgency: Urgency

    public static let hours = 12

    public init(report: SkyReport, outlook: HourlyOutlook, urgency: Urgency, timeZone: TimeZone) {
        let clock = HourlyOutlook.clock(timeZone)
        let now = HourlyOutlook.degrees(report.current.temperature)
        let next = Array(outlook.hours.prefix(Self.hours))
        let wet = next.filter { $0.precipitation >= 0.1 }

        glance = report.rain == .dry ? now : "☂︎ \(now)"

        let what: String
        if let hazard = report.hazards.first {
            switch hazard {
            case .thunder(let at): what = "thunder from \(clock.string(from: at))"
            case .storm(let at, _): what = "storm wind from \(clock.string(from: at))"
            case .heat: what = "dangerous heat"
            }
        } else {
            switch report.rain {
            case .soon: what = "rain within the hour"
            case .now(let until, _): what = "rain until \(clock.string(from: until))"
            case .later(let at, _): what = "rain from \(clock.string(from: at))"
            case .dry: what = report.current.symbol?.phrase.lowercased() ?? "dry"
            }
        }
        title = Self.clip("\(now) · \(what)", 28)

        if let first = wet.first, let last = wet.last {
            let total = wet.reduce(0) { $0 + $1.precipitation }
            let span = "\(clock.string(from: first.time))–\(clock.string(from: last.time.addingTimeInterval(3600)))"
            subtitle = Self.clip("Rain \(span), \(HourlyOutlook.millimetres(total)) in all", 60)
            bars = .rain(next.map(\.precipitation))
        } else {
            let temps = next.map(\.temperature)
            if let high = temps.max(), let low = temps.min() {
                subtitle = "Dry for \(next.count) hours · high \(HourlyOutlook.degrees(high)), low \(HourlyOutlook.degrees(low))"
            } else {
                subtitle = "No hourly forecast yet."
            }
            bars = .temperature(temps)
        }
        self.urgency = urgency
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
