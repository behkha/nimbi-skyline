import Foundation

/// Air quality and pollen by the hour, from CAMS (the Copernicus Atmosphere Monitoring Service)
/// through Open-Meteo's air quality API. Air quality covers the world; pollen only Europe, so
/// elsewhere every pollen value is nil.
public struct AirQuality: Equatable, Sendable {
    public struct Hour: Equatable, Sendable {
        public var time: Date
        public var europeanAQI: Double?
        public var usAQI: Double?
        /// µg/m³.
        public var pm25: Double?
        public var pm10: Double?
        public var ozone: Double?
        public var nitrogenDioxide: Double?
        public var sulphurDioxide: Double?
        /// Grains/m³ by kind; a kind is missing where CAMS has no pollen forecast.
        public var pollen: [Pollen: Double]

        public init(time: Date, europeanAQI: Double? = nil, usAQI: Double? = nil, pm25: Double? = nil,
                    pm10: Double? = nil, ozone: Double? = nil, nitrogenDioxide: Double? = nil,
                    sulphurDioxide: Double? = nil, pollen: [Pollen: Double] = [:]) {
            self.time = time
            self.europeanAQI = europeanAQI
            self.usAQI = usAQI
            self.pm25 = pm25
            self.pm10 = pm10
            self.ozone = ozone
            self.nitrogenDioxide = nitrogenDioxide
            self.sulphurDioxide = sulphurDioxide
            self.pollen = pollen
        }

        public func index(_ scale: AirScale) -> AirLevel? {
            switch scale {
            case .european: return europeanAQI.map { AirLevel(value: $0, scale: .european) }
            case .us: return usAQI.map { AirLevel(value: $0, scale: .us) }
            }
        }

        /// The strongest pollen right now, if any kind reaches "low".
        public var strongestPollen: (kind: Pollen, level: PollenLevel)? {
            pollen.map { ($0.key, $0.key.level($0.value)) }
                .filter { $0.1 > .none }
                .max { $0.1 == $1.1 ? $0.0.rawValue > $1.0.rawValue : $0.1 < $1.1 }
        }
    }

    public var hours: [Hour]

    public init(hours: [Hour]) { self.hours = hours.sorted { $0.time < $1.time } }

    /// The hour that covers `date`.
    public func hour(at date: Date) -> Hour? {
        hours.last { $0.time <= date && date < $0.time.addingTimeInterval(3600) }
    }

    /// True where CAMS forecasts pollen (Europe).
    public var hasPollen: Bool { hours.contains { !$0.pollen.isEmpty } }
}

/// The two common air quality indexes. Skyline uses the US one in the US, the European one elsewhere.
public enum AirScale: String, Codable, CaseIterable, Sendable {
    case european, us

    public static var forRegion: AirScale {
        Locale.current.region?.identifier == "US" ? .us : .european
    }

    public var title: String { self == .us ? "US AQI" : "European AQI" }
}

/// An index value with its band: 0 is the best band, 5 the worst.
public struct AirLevel: Equatable, Sendable {
    public var value: Double
    public var scale: AirScale

    public var band: Int {
        let bounds: [Double] = scale == .european ? [20, 40, 60, 80, 100] : [50, 100, 150, 200, 300]
        return bounds.firstIndex { value <= $0 } ?? 5
    }

    public var name: String {
        let names = scale == .european
            ? ["Good", "Fair", "Moderate", "Poor", "Very poor", "Extremely poor"]
            : ["Good", "Moderate", "Unhealthy for some", "Unhealthy", "Very unhealthy", "Hazardous"]
        return names[band]
    }

    /// Worth a second look (amber): European "Poor", US "Unhealthy" or worse.
    public var isPoor: Bool { band >= 3 }
    /// Worth a notice: European "Very poor", US "Very unhealthy" or worse.
    public var isBad: Bool { band >= 4 }
    /// Where the value sits on the scale, 0…1, for a meter.
    public var fraction: Double { min(1, value / (scale == .european ? 120 : 350)) }
}

public enum Pollen: String, CaseIterable, Codable, Sendable {
    case alder, birch, grass, mugwort, olive, ragweed

    public var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Grains/m³ where low, moderate, high and very high start. Approximate, after the bands
    /// European pollen services use: trees release far more than grasses and weeds.
    var thresholds: [Double] {
        switch self {
        case .alder, .birch, .olive: return [1, 20, 100, 500]
        case .grass: return [1, 10, 50, 150]
        case .mugwort, .ragweed: return [1, 10, 50, 200]
        }
    }

    public func level(_ grains: Double) -> PollenLevel {
        PollenLevel(rawValue: thresholds.lastIndex { grains >= $0 }.map { $0 + 1 } ?? 0) ?? .none
    }
}

public enum PollenLevel: Int, Comparable, Sendable {
    case none, low, moderate, high, veryHigh

    public static func < (a: PollenLevel, b: PollenLevel) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .none: return "none"
        case .low: return "low"
        case .moderate: return "moderate"
        case .high: return "high"
        case .veryHigh: return "very high"
        }
    }
}

// MARK: - Open-Meteo's air quality API

extension AirQuality {
    public static let variables = ["european_aqi", "us_aqi", "pm2_5", "pm10", "ozone", "nitrogen_dioxide",
                                   "sulphur_dioxide"] + Pollen.allCases.map { "\($0.rawValue)_pollen" }

    /// Decodes Open-Meteo's hourly response (requested with `timeformat=unixtime`).
    public static func decodeOpenMeteo(_ data: Data) throws -> AirQuality {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let times = hourly["time"] as? [Double] else { throw METError.undecodable }
        func series(_ name: String) -> [Double?] {
            (hourly[name] as? [Any])?.map { $0 as? Double ?? ($0 as? Int).map(Double.init) } ?? []
        }
        func at(_ values: [Double?], _ i: Int) -> Double? { i < values.count ? values[i] : nil }
        let eaqi = series("european_aqi"), us = series("us_aqi"), pm25 = series("pm2_5"), pm10 = series("pm10")
        let o3 = series("ozone"), no2 = series("nitrogen_dioxide"), so2 = series("sulphur_dioxide")
        let pollen = Dictionary(uniqueKeysWithValues: Pollen.allCases.map { ($0, series("\($0.rawValue)_pollen")) })
        let hours = times.enumerated().map { i, t in
            Hour(time: Date(timeIntervalSince1970: t), europeanAQI: at(eaqi, i), usAQI: at(us, i),
                 pm25: at(pm25, i), pm10: at(pm10, i), ozone: at(o3, i), nitrogenDioxide: at(no2, i),
                 sulphurDioxide: at(so2, i),
                 pollen: pollen.reduce(into: [:]) { result, kind in
                     if let v = at(kind.value, i) { result[kind.key] = v }
                 })
        }
        return AirQuality(hours: hours)
    }
}

public struct AirResult: Sendable {
    public var air: AirQuality
    public var fetchedAt: Date
    public var expires: Date
}

/// Fetches air quality politely: one request per ~1 km cell an hour at most (CAMS updates a few
/// times a day), cached on disk across relaunches, backing off after failures. The position
/// sent is rounded to two decimals.
public actor AirClient {
    public static let baseURL = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
    static let lifetime: TimeInterval = 60 * 60
    static let minimumBackoff: TimeInterval = 60
    static let maximumBackoff: TimeInterval = 60 * 60

    private let transport: HTTPTransport
    private let store: ForecastStore
    private let now: @Sendable () -> Date
    private let userAgent: String
    private var backoff: [String: (until: Date, failures: Int)] = [:]

    public init(transport: HTTPTransport = URLSession.skyline(),
                store: ForecastStore = DiskForecastStore(directory: FileManager.default
                    .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("app.nimbi.skyline/air", isDirectory: true)),
                userAgent: String = METConfiguration.defaultUserAgent,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.store = store
        self.userAgent = userAgent
        self.now = now
    }

    public static func url(for coordinate: Coordinate) -> URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            URLQueryItem(name: "hourly", value: AirQuality.variables.joined(separator: ",")),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "GMT"),
        ]
        return c.url!
    }

    static func key(_ c: Coordinate) -> String { String(format: "%.2f_%.2f", c.latitude, c.longitude) }

    public func air(for coordinate: Coordinate) async throws -> AirResult {
        let key = Self.key(coordinate)
        let cached = store.load(key)
        let date = now()
        if let cached, date < cached.expires, let air = try? AirQuality.decodeOpenMeteo(cached.body) {
            return AirResult(air: air, fetchedAt: cached.fetchedAt, expires: cached.expires)
        }
        if let wait = backoff[key], date < wait.until {
            if let stale = stale(cached) { return stale }
            throw METError.backingOff(until: wait.until)
        }
        var request = URLRequest(url: Self.url(for: coordinate))
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await transport.send(request)
            guard response.statusCode == 200, let air = try? AirQuality.decodeOpenMeteo(data) else {
                fail(key)
                if let stale = stale(cached) { return stale }
                throw METError.http(status: response.statusCode)
            }
            let entry = CachedForecast(body: data, expires: now().addingTimeInterval(Self.lifetime),
                                       lastModified: nil, fetchedAt: now())
            store.save(entry, for: key)
            backoff[key] = nil
            return AirResult(air: air, fetchedAt: entry.fetchedAt, expires: entry.expires)
        } catch let error as METError {
            throw error
        } catch {
            fail(key)
            if let stale = stale(cached) { return stale }
            throw error
        }
    }

    /// When the next request for `coordinate` is allowed.
    public func nextRefresh(for coordinate: Coordinate) -> Date? {
        let key = Self.key(coordinate)
        return [store.load(key)?.expires, backoff[key]?.until].compactMap { $0 }.max()
    }

    private func stale(_ cached: CachedForecast?) -> AirResult? {
        guard let cached, let air = try? AirQuality.decodeOpenMeteo(cached.body) else { return nil }
        return AirResult(air: air, fetchedAt: cached.fetchedAt, expires: cached.expires)
    }

    private func fail(_ key: String) {
        let failures = (backoff[key]?.failures ?? 0) + 1
        let wait = min(Self.maximumBackoff, Self.minimumBackoff * pow(2, Double(failures - 1)))
        backoff[key] = (now().addingTimeInterval(wait), failures)
    }
}
