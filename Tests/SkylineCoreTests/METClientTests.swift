import Foundation
import Testing
@testable import SkylineCore

@Suite struct CoordinateTests {
    @Test func truncatesToFourDecimalsTowardZero() {
        let c = Coordinate(latitude: 59.913_987_6, longitude: -10.752_29).truncated()
        #expect(c.latitude == 59.9139)
        #expect(c.longitude == -10.7522)
    }

    @Test func formatsWithoutTrailingZeros() {
        #expect(Coordinate.format(59.91) == "59.91")
        #expect(Coordinate.format(10) == "10")
        #expect(Coordinate.format(-0.00001) == "0")
        #expect(Coordinate(latitude: 59.913_99, longitude: 10.75).cacheKey == "59.9139_10.75")
    }

    @Test func requestURLCarriesAtMostFourDecimals() {
        let url = METConfiguration.direct.forecastURL(for: Coordinate(latitude: 59.913_987_6, longitude: 10.752_291))
        #expect(url.absoluteString == "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=59.9139&lon=10.7522")
    }

    @Test func proxyKeepsTheSamePath() {
        let proxy = METConfiguration(baseURL: URL(string: "https://skyline-proxy.example.workers.dev")!)
        let url = proxy.forecastURL(for: Fixture.oslo)
        #expect(url.absoluteString == "https://skyline-proxy.example.workers.dev/weatherapi/locationforecast/2.0/compact?lat=59.9139&lon=10.7522")
    }

    @Test func distanceIsRoughlyRight() {
        let bergen = Coordinate(latitude: 60.3913, longitude: 5.3221)
        #expect(abs(Fixture.oslo.distance(to: bergen) - 305_000) < 5_000)
    }
}

@Suite struct DecodingTests {
    @Test func decodesCompactSteps() throws {
        var wet = Fixture.Hour(); wet.symbol = "lightrain"; wet.precipitation = 0.4
        let data = Fixture.json(hours: [Fixture.Hour(), wet], sixHourly: 2)
        let forecast = try Forecast.decodeMET(data)
        #expect(forecast.steps.count == 4)
        #expect(forecast.coordinate.latitude == Fixture.oslo.latitude)
        #expect(forecast.steps[1].symbol?.base == "lightrain")
        #expect(forecast.steps[1].precipitation == 0.4)
        #expect(forecast.steps[1].period == 3600)
        #expect(forecast.steps[2].period == 6 * 3600)
        #expect(forecast.steps[0].time == Fixture.t0)
    }

    @Test func readsSymbolVariants() {
        let s = WeatherSymbol("lightrainshowersandthunder_polartwilight")
        #expect(s.base == "lightrainshowersandthunder")
        #expect(s.variant == .polartwilight)
        #expect(s.isThunder)
        #expect(s.isPrecipitation)
        #expect(!WeatherSymbol("partlycloudy_day").isPrecipitation)
        #expect(WeatherSymbol("heavysnow").severity > WeatherSymbol("lightsnow").severity)
    }
}

@Suite struct METClientTests {
    let expires = "Sat, 10 Oct 2026 14:30:00 GMT"
    let lastModified = "Sat, 10 Oct 2026 13:55:00 GMT"

    func ok(_ expires: String) -> ScriptedTransport.Reply {
        .init(status: 200, headers: ["Expires": expires, "Last-Modified": lastModified],
              body: Fixture.json(hours: Fixture.dry(3)))
    }

    @Test func sendsIdentifyingUserAgent() async throws {
        let transport = ScriptedTransport([ok(expires)])
        let clock = TestClock(Fixture.t0)
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { clock.now })
        let result = try await client.forecast(for: Fixture.oslo)
        #expect(result.source == .network)
        let ua = transport.requests[0].value(forHTTPHeaderField: "User-Agent") ?? ""
        #expect(ua.contains("Skyline/"))
        #expect(ua.contains("github.com/behkha/nimbi-skyline"))
        #expect(transport.requests[0].value(forHTTPHeaderField: "If-Modified-Since") == nil)
    }

    @Test func neverAsksAgainBeforeExpires() async throws {
        let transport = ScriptedTransport([ok(expires)])
        let clock = TestClock(Fixture.t0)
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { clock.now })
        _ = try await client.forecast(for: Fixture.oslo)
        clock.advance(29 * 60)
        let again = try await client.forecast(for: Fixture.oslo)
        #expect(again.source == .cache)
        #expect(transport.requestCount == 1)
        // GPS jitter below 4 decimals is the same cache entry.
        _ = try await client.forecast(for: Coordinate(latitude: 59.913_94, longitude: 10.752_28))
        #expect(transport.requestCount == 1)
    }

    @Test func revalidatesWithIfModifiedSinceAfterExpires() async throws {
        let later = "Sat, 10 Oct 2026 15:00:00 GMT"
        let transport = ScriptedTransport([ok(expires), .init(status: 304, headers: ["Expires": later])])
        let clock = TestClock(Fixture.t0)
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { clock.now })
        _ = try await client.forecast(for: Fixture.oslo)
        clock.advance(31 * 60)
        let result = try await client.forecast(for: Fixture.oslo)
        #expect(result.source == .revalidated)
        #expect(result.expires == HTTPDate.parse(later))
        #expect(transport.requests[1].value(forHTTPHeaderField: "If-Modified-Since") == lastModified)
        #expect(result.forecast.steps.count == 3)
        // The new Expires holds: nothing more until 15:00.
        clock.advance(20 * 60)
        #expect(try await client.forecast(for: Fixture.oslo).source == .cache)
        #expect(transport.requestCount == 2)
    }

    @Test func backsOffOn429AndServesStale() async throws {
        let transport = ScriptedTransport([ok(expires), .init(status: 429, headers: ["Retry-After": "120"])])
        let clock = TestClock(Fixture.t0)
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { clock.now })
        _ = try await client.forecast(for: Fixture.oslo)
        clock.advance(31 * 60)
        let stale = try await client.forecast(for: Fixture.oslo)
        #expect(stale.source == .stale)
        #expect(transport.requestCount == 2)
        // Inside the backoff: no request at all.
        clock.advance(100)
        #expect(try await client.forecast(for: Fixture.oslo).source == .stale)
        #expect(transport.requestCount == 2)
        let next = await client.nextRefresh(for: Fixture.oslo)
        #expect(next == Fixture.t0.addingTimeInterval(31 * 60 + 120))
    }

    @Test func backoffDoublesWithoutRetryAfter() async throws {
        let transport = ScriptedTransport([.init(status: 503), .init(status: 503)])
        let clock = TestClock(Fixture.t0)
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { clock.now })
        await #expect(throws: METError.backingOff(until: Fixture.t0.addingTimeInterval(60))) {
            try await client.forecast(for: Fixture.oslo)
        }
        clock.advance(61)
        await #expect(throws: METError.backingOff(until: Fixture.t0.addingTimeInterval(61 + 120))) {
            try await client.forecast(for: Fixture.oslo)
        }
        #expect(transport.requestCount == 2)
    }

    @Test func forbiddenIsItsOwnError() async {
        let transport = ScriptedTransport([.init(status: 403)])
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { Fixture.t0 })
        await #expect(throws: METError.forbidden) { try await client.forecast(for: Fixture.oslo) }
    }

    @Test func rejectsInvalidCoordinates() async {
        let transport = ScriptedTransport([])
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { Fixture.t0 })
        await #expect(throws: METError.invalidCoordinate) {
            try await client.forecast(for: Coordinate(latitude: 91, longitude: 0))
        }
        #expect(transport.requestCount == 0)
    }

    @Test func missingExpiresFallsBackToTenMinutes() async throws {
        let transport = ScriptedTransport([.init(status: 200, body: Fixture.json(hours: Fixture.dry(2)))])
        let client = METClient(configuration: .direct, transport: transport, store: MemoryForecastStore(), now: { Fixture.t0 })
        let result = try await client.forecast(for: Fixture.oslo)
        #expect(result.expires == Fixture.t0.addingTimeInterval(600))
    }

    @Test func diskStoreSurvivesARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = CachedForecast(body: Data("{}".utf8), expires: Fixture.t0, lastModified: lastModified, fetchedAt: Fixture.t0)
        DiskForecastStore(directory: dir).save(entry, for: Fixture.oslo.cacheKey)
        #expect(DiskForecastStore(directory: dir).load(Fixture.oslo.cacheKey) == entry)
    }

    @Test func parsesRetryAfterBothWays() {
        #expect(METClient.retryAfter("90", now: Fixture.t0) == 90)
        #expect(METClient.retryAfter("Sat, 10 Oct 2026 14:05:00 GMT", now: Fixture.t0) == 300)
        #expect(METClient.retryAfter("soon", now: Fixture.t0) == nil)
    }
}
