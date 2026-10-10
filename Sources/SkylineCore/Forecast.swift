import Foundation

/// One forecast, as Skyline uses it: MET's compact timeseries flattened into steps.
public struct Forecast: Equatable, Sendable {
    /// Where MET says the forecast is for (its grid point, not exactly the request).
    public var coordinate: Coordinate
    /// When MET last ran the model for this point.
    public var updatedAt: Date
    /// Ascending by time. Hourly for about two and a half days, then six-hourly.
    public var steps: [ForecastStep]

    public init(coordinate: Coordinate, updatedAt: Date, steps: [ForecastStep]) {
        self.coordinate = coordinate
        self.updatedAt = updatedAt
        self.steps = steps
    }
}

public struct ForecastStep: Equatable, Sendable {
    /// Start of the step. Instant values hold at this moment; the period runs from here.
    public var time: Date
    /// °C at `time`.
    public var temperature: Double
    /// m/s at `time` (10 min mean). Gusts are only in MET's "complete" product.
    public var windSpeed: Double?
    public var windFromDirection: Double?
    public var humidity: Double?
    public var cloudCover: Double?
    /// The weather for the period that starts at `time`.
    public var symbol: WeatherSymbol?
    /// mm over the period.
    public var precipitation: Double?
    /// Length of the period `symbol` and `precipitation` describe: 1 h, or 6 h further out.
    public var period: TimeInterval

    public init(time: Date, temperature: Double, windSpeed: Double? = nil, windFromDirection: Double? = nil,
                humidity: Double? = nil, cloudCover: Double? = nil, symbol: WeatherSymbol? = nil,
                precipitation: Double? = nil, period: TimeInterval = 3600) {
        self.time = time
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.windFromDirection = windFromDirection
        self.humidity = humidity
        self.cloudCover = cloudCover
        self.symbol = symbol
        self.precipitation = precipitation
        self.period = period
    }

    public var end: Date { time.addingTimeInterval(period) }

    /// mm per hour over the period.
    public var precipitationRate: Double { (precipitation ?? 0) / max(1, period / 3600) }

    /// Rain, sleet or snow in this period. MET's symbols already apply its own thresholds, so a
    /// wet symbol counts even with a tiny amount, and 0.1 mm counts even under a dry symbol.
    public var isWet: Bool { (symbol?.isPrecipitation ?? false) || (precipitation ?? 0) >= 0.1 }
}

/// A MET weather symbol code, such as `lightrainshowers_day` or `heavyrainandthunder`.
/// List: https://api.met.no/weatherapi/weathericon/2.0/documentation
public struct WeatherSymbol: Hashable, Sendable {
    public enum Variant: String, Sendable { case day, night, polartwilight }

    /// The code as MET sends it.
    public var code: String
    /// The code without its `_day` / `_night` / `_polartwilight` suffix.
    public var base: String
    public var variant: Variant?

    public init(_ code: String) {
        self.code = code
        if let underscore = code.lastIndex(of: "_"),
           let variant = Variant(rawValue: String(code[code.index(after: underscore)...])) {
            self.base = String(code[..<underscore])
            self.variant = variant
        } else {
            self.base = code
            self.variant = nil
        }
    }

    public var isThunder: Bool { base.contains("thunder") }
    public var isSnow: Bool { base.contains("snow") }
    public var isSleet: Bool { base.contains("sleet") }
    public var isPrecipitation: Bool {
        base.contains("rain") || base.contains("sleet") || base.contains("snow") || base.contains("showers")
    }
    /// Base codes MET ranks from clear to heavy, so a day can pick its most notable weather.
    public var severity: Int {
        if isThunder { return 6 }
        if base.hasPrefix("heavy") { return 5 }
        if isPrecipitation { return base.hasPrefix("light") ? 3 : 4 }
        switch base {
        case "fog": return 2
        case "cloudy": return 2
        case "partlycloudy": return 1
        case "fair": return 1
        default: return 0 // clearsky
        }
    }
}

// MARK: - MET compact JSON

/// The `compact` response of Locationforecast 2.0, only the fields Skyline reads.
struct METCompact: Decodable {
    struct Geometry: Decodable { var coordinates: [Double] }
    struct Properties: Decodable {
        struct Meta: Decodable { var updatedAt: Date }
        var meta: Meta
        var timeseries: [Step]
    }
    struct Step: Decodable {
        var time: Date
        var data: StepData
    }
    struct StepData: Decodable {
        struct Instant: Decodable { var details: InstantDetails }
        struct InstantDetails: Decodable {
            var airTemperature: Double?
            var windSpeed: Double?
            var windFromDirection: Double?
            var relativeHumidity: Double?
            var cloudAreaFraction: Double?
        }
        struct Period: Decodable {
            struct Summary: Decodable { var symbolCode: String }
            struct Details: Decodable { var precipitationAmount: Double? }
            var summary: Summary?
            var details: Details?
        }
        var instant: Instant
        // `.convertFromSnakeCase` turns "next_1_hours" into "next1Hours".
        var next1Hours: Period?
        var next6Hours: Period?
        var next12Hours: Period?
    }
    var geometry: Geometry
    var properties: Properties
}

extension Forecast {
    /// Decodes MET's compact JSON. Steps without a temperature are skipped.
    public static func decodeMET(_ data: Data) throws -> Forecast {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let compact = try decoder.decode(METCompact.self, from: data)
        let c = compact.geometry.coordinates
        let coordinate = Coordinate(latitude: c.count > 1 ? c[1] : 0, longitude: c.first ?? 0)
        let steps: [ForecastStep] = compact.properties.timeseries.compactMap { step in
            let d = step.data
            guard let temperature = d.instant.details.airTemperature else { return nil }
            let period: METCompact.StepData.Period?
            let length: TimeInterval
            if let p = d.next1Hours { period = p; length = 3600 }
            else if let p = d.next6Hours { period = p; length = 6 * 3600 }
            else if let p = d.next12Hours { period = p; length = 12 * 3600 }
            else { period = nil; length = 3600 }
            return ForecastStep(time: step.time,
                                temperature: temperature,
                                windSpeed: d.instant.details.windSpeed,
                                windFromDirection: d.instant.details.windFromDirection,
                                humidity: d.instant.details.relativeHumidity,
                                cloudCover: d.instant.details.cloudAreaFraction,
                                symbol: period?.summary.map { WeatherSymbol($0.symbolCode) },
                                precipitation: period?.details?.precipitationAmount,
                                period: length)
        }
        return Forecast(coordinate: coordinate, updatedAt: compact.properties.meta.updatedAt,
                        steps: steps.sorted { $0.time < $1.time })
    }
}
