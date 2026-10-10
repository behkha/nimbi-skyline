import Foundation

/// Where forecasts come from and who's asking. The proxy in `worker/` serves the same path and
/// query as api.met.no, so switching is only a different `baseURL`.
public struct METConfiguration: Equatable, Sendable {
    public var baseURL: URL
    /// MET requires an identifying User-Agent with a way to reach the maker.
    public var userAgent: String

    public init(baseURL: URL, userAgent: String = METConfiguration.defaultUserAgent) {
        self.baseURL = baseURL
        self.userAgent = userAgent
    }

    public static let defaultUserAgent = "Skyline/0.1 github.com/behkha/nimbi-skyline behzadkhanlar@gmail.com"
    public static let metBaseURL = URL(string: "https://api.met.no")!
    /// Straight to MET. Fine for development; shipped builds should go through the proxy.
    public static let direct = METConfiguration(baseURL: metBaseURL)

    /// The proxy when one is configured (`SkylineProxyURL` in defaults or Info.plist), else direct.
    public static func current(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> METConfiguration {
        let raw = defaults.string(forKey: "SkylineProxyURL")
            ?? bundle.object(forInfoDictionaryKey: "SkylineProxyURL") as? String
        if let raw, !raw.isEmpty, let url = URL(string: raw), url.scheme == "https" {
            return METConfiguration(baseURL: url)
        }
        return .direct
    }

    public func forecastURL(for coordinate: Coordinate, altitude: Int? = nil) -> URL {
        let point = coordinate.truncated()
        var components = URLComponents(url: baseURL.appendingPathComponent("weatherapi/locationforecast/2.0/compact"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lat", value: Coordinate.format(point.latitude)),
                                 URLQueryItem(name: "lon", value: Coordinate.format(point.longitude))]
        if let altitude { components.queryItems?.append(URLQueryItem(name: "altitude", value: String(altitude))) }
        return components.url!
    }
}

/// The network, behind a seam so tests can script MET's answers.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    /// A session that leaves caching to `METClient`, which follows MET's headers itself.
    public static func skyline() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }
}

public enum METError: Error, Equatable {
    /// MET (or the proxy) asked us to slow down and there's nothing cached to show meanwhile.
    case backingOff(until: Date)
    /// 403: usually a missing or banned User-Agent.
    case forbidden
    case http(status: Int)
    case invalidCoordinate
    case undecodable
}

public struct ForecastResult: Sendable {
    public enum Source: Equatable, Sendable {
        /// From the cache, still before `Expires`: no request was made.
        case cache
        /// A fresh 200 from the network.
        case network
        /// A 304: the cached body is still current and its `Expires` moved on.
        case revalidated
        /// Past `Expires` but the network failed or asked us to back off.
        case stale
    }

    public var forecast: Forecast
    public var source: Source
    public var expires: Date
    /// When the body was first downloaded.
    public var fetchedAt: Date
}

/// Fetches Locationforecast 2.0 compact the way MET's terms ask: one identifying User-Agent,
/// coordinates truncated to 4 decimals, every response cached until its `Expires`, conditional
/// requests with `If-Modified-Since`, and backing off on 429 and server errors.
public actor METClient {
    public nonisolated let configuration: METConfiguration
    private let transport: HTTPTransport
    private let store: ForecastStore
    private let now: @Sendable () -> Date
    private var backoff: [String: (until: Date, failures: Int)] = [:]

    /// Used when MET leaves out `Expires`, which it shouldn't.
    static let fallbackLifetime: TimeInterval = 10 * 60
    static let minimumBackoff: TimeInterval = 60
    static let maximumBackoff: TimeInterval = 60 * 60

    public init(configuration: METConfiguration = .current(),
                transport: HTTPTransport = URLSession.skyline(),
                store: ForecastStore = DiskForecastStore(),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.transport = transport
        self.store = store
        self.now = now
    }

    /// The forecast for `coordinate`, from the cache when it hasn't expired. There is no "force"
    /// option on purpose: MET's terms forbid asking again before `Expires`.
    public func forecast(for coordinate: Coordinate) async throws -> ForecastResult {
        guard coordinate.isValid else { throw METError.invalidCoordinate }
        let key = coordinate.cacheKey
        let cached = store.load(key)
        let date = now()

        if let cached, date < cached.expires, let forecast = try? Forecast.decodeMET(cached.body) {
            return ForecastResult(forecast: forecast, source: .cache, expires: cached.expires, fetchedAt: cached.fetchedAt)
        }
        if let wait = backoff[key], date < wait.until {
            if let stale = staleResult(cached) { return stale }
            throw METError.backingOff(until: wait.until)
        }

        var request = URLRequest(url: configuration.forecastURL(for: coordinate))
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let lastModified = cached?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            noteFailure(key, retryAfter: nil)
            if let stale = staleResult(cached) { return stale }
            throw error
        }

        let received = now()
        switch response.statusCode {
        case 200, 203: // 203: the product is deprecated but still served.
            guard let forecast = try? Forecast.decodeMET(data) else { throw METError.undecodable }
            let entry = CachedForecast(body: data,
                                       expires: expires(from: response, received: received),
                                       lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
                                       fetchedAt: received)
            store.save(entry, for: key)
            backoff[key] = nil
            return ForecastResult(forecast: forecast, source: .network, expires: entry.expires, fetchedAt: received)

        case 304:
            guard var entry = cached, let forecast = try? Forecast.decodeMET(entry.body) else {
                throw METError.http(status: 304)
            }
            entry.expires = expires(from: response, received: received)
            if let lastModified = response.value(forHTTPHeaderField: "Last-Modified") { entry.lastModified = lastModified }
            store.save(entry, for: key)
            backoff[key] = nil
            return ForecastResult(forecast: forecast, source: .revalidated, expires: entry.expires, fetchedAt: entry.fetchedAt)

        case 429, 500...599:
            noteFailure(key, retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: received))
            if let stale = staleResult(cached) { return stale }
            throw METError.backingOff(until: backoff[key]!.until)

        case 403:
            throw METError.forbidden
        default:
            throw METError.http(status: response.statusCode)
        }
    }

    /// When the next request for `coordinate` is allowed: its cache's `Expires`, or the end of a
    /// backoff. The app schedules its refresh for this moment instead of polling.
    public func nextRefresh(for coordinate: Coordinate) -> Date? {
        let key = coordinate.cacheKey
        return [store.load(key)?.expires, backoff[key]?.until].compactMap { $0 }.max()
    }

    private func staleResult(_ cached: CachedForecast?) -> ForecastResult? {
        guard let cached, let forecast = try? Forecast.decodeMET(cached.body) else { return nil }
        return ForecastResult(forecast: forecast, source: .stale, expires: cached.expires, fetchedAt: cached.fetchedAt)
    }

    /// Doubles the wait with each failure in a row (60 s, 2 min, 4 min … 1 h), or follows
    /// `Retry-After` when that's longer.
    private func noteFailure(_ key: String, retryAfter: TimeInterval?) {
        let failures = (backoff[key]?.failures ?? 0) + 1
        let doubling = min(Self.maximumBackoff, Self.minimumBackoff * pow(2, Double(failures - 1)))
        let wait = max(doubling, min(Self.maximumBackoff * 6, retryAfter ?? 0))
        backoff[key] = (now().addingTimeInterval(wait), failures)
    }

    private func expires(from response: HTTPURLResponse, received: Date) -> Date {
        if let header = response.value(forHTTPHeaderField: "Expires"), let date = HTTPDate.parse(header) {
            return date
        }
        return received.addingTimeInterval(Self.fallbackLifetime)
    }

    /// `Retry-After` is either seconds or an HTTP date.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        if let date = HTTPDate.parse(value) { return max(0, date.timeIntervalSince(now)) }
        return nil
    }
}

/// RFC 7231 dates, as in `Expires: Sat, 10 Oct 2026 14:30:12 GMT`.
enum HTTPDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
    private static let lock = NSLock()

    static func parse(_ text: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return formatter.date(from: text)
    }

    static func format(_ date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return formatter.string(from: date)
    }
}
