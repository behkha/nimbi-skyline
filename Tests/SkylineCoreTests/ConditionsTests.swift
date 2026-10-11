import Foundation
import Testing
@testable import SkylineCore

private typealias Hour = Fixture.Hour

/// 14:20 UTC, 16:20 in Oslo: the sun is up, sunset around 18:30 local.
private let afternoon = Fixture.t0.addingTimeInterval(20 * 60)
private let oslo = TimeZone(identifier: "Europe/Oslo")!

private func air(_ eaqi: Double, pollen: [Pollen: Double] = [:]) -> AirQuality {
    AirQuality(hours: (0..<24).map {
        AirQuality.Hour(time: Fixture.t0.addingTimeInterval(Double($0) * 3600), europeanAQI: eaqi, usAQI: eaqi * 1.5,
                        pm25: 4, pollen: pollen)
    })
}

@Suite struct CompleteProductTests {
    @Test func decodesTheExtras() throws {
        var h = Hour()
        h.instant = ["apparent_air_temperature": 9.5, "wind_speed_of_gust": 12.1, "ultraviolet_index_clear_sky": 3.2,
                     "air_temperature_percentile_10": 11, "air_temperature_percentile_90": 13.5, "dew_point_temperature": 7,
                     "fog_area_fraction": 0, "cloud_area_fraction_high": 70]
        h.details = ["probability_of_precipitation": 39.1, "probability_of_thunder": 0.1,
                     "precipitation_amount_min": 0, "precipitation_amount_max": 0.3]
        let step = try #require(Fixture.forecast([h]).steps.first)
        #expect(step.apparentTemperature == 9.5)
        #expect(step.windGust == 12.1)
        #expect(step.uvClearSky == 3.2)
        #expect(step.temperatureLow == 11 && step.temperatureHigh == 13.5)
        #expect(step.precipitationChance == 39.1 && step.thunderChance == 0.1)
        #expect(step.precipitationMax == 0.3)
        #expect(step.cloudHigh == 70 && step.dewPoint == 7 && step.pressure == 1012.3)
    }

    @Test func compactStillDecodes() throws {
        let step = try #require(Fixture.forecast(Fixture.dry(1)).steps.first)
        #expect(step.apparentTemperature == nil && step.uvClearSky == nil)
    }
}

@Suite struct SunTimesTests {
    @Test func osloInOctober() throws {
        let (rise, set) = Sun.times(on: afternoon, coordinate: Fixture.oslo, timeZone: oslo)
        let clock = HourlyOutlook.clock(oslo)
        // Oslo, 10 Oct 2026: sunrise about 07:55, sunset about 18:30 (CEST).
        let r = try #require(rise), s = try #require(set)
        #expect(abs(r.timeIntervalSince(clock.date(from: "07:55")!.onDay(of: afternoon, oslo))) < 15 * 60)
        #expect(abs(s.timeIntervalSince(clock.date(from: "18:30")!.onDay(of: afternoon, oslo))) < 15 * 60)
    }

    @Test func nextEventIsTonightsSunset() throws {
        guard case .set = try #require(Sun.next(after: afternoon, coordinate: Fixture.oslo)) else {
            Issue.record("expected a sunset next"); return
        }
    }

    @Test func midnightSunHasNoEvents() {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        let midsummer = Date(timeIntervalSince1970: 1_782_043_200) // 21 Jun 2026, 12:00 UTC
        #expect(Sun.events(from: midsummer, to: midsummer.addingTimeInterval(86_400), coordinate: tromso).isEmpty)
    }
}

@Suite struct AirQualityTests {
    @Test func decodesOpenMeteo() throws {
        let json = """
        {"hourly":{"time":[1791640800,1791644400],"european_aqi":[18,85],"us_aqi":[26,160],"pm2_5":[1.3,40],
         "birch_pollen":[0.0,120.5],"grass_pollen":[null,null]}}
        """
        let air = try AirQuality.decodeOpenMeteo(Data(json.utf8))
        #expect(air.hours.count == 2)
        let later = try #require(air.hour(at: Fixture.t0.addingTimeInterval(3600 + 60)))
        #expect(later.index(.european)?.name == "Very poor")
        #expect(later.index(.us)?.name == "Unhealthy")
        #expect(later.pollen[.grass] == nil)
        #expect(later.strongestPollen?.kind == .birch && later.strongestPollen?.level == .high)
    }

    @Test func bands() {
        #expect(AirLevel(value: 15, scale: .european).name == "Good")
        #expect(AirLevel(value: 61, scale: .european).isPoor)
        #expect(!AirLevel(value: 61, scale: .european).isBad)
        #expect(AirLevel(value: 120, scale: .european).name == "Extremely poor")
        #expect(AirLevel(value: 210, scale: .us).isBad)
        #expect(Pollen.grass.level(60) == .high)
        #expect(Pollen.birch.level(60) == .moderate)
        #expect(Pollen.ragweed.level(0) == .none)
    }

    @Test func cachesForAnHourAndRoundsThePosition() async throws {
        let body = Data(#"{"hourly":{"time":[1791640800],"european_aqi":[18]}}"#.utf8)
        let transport = ScriptedTransport([ScriptedTransport.Reply(status: 200, body: body)])
        let clock = TestClock(Fixture.t0)
        let client = AirClient(transport: transport, store: MemoryForecastStore(), now: { clock.now })
        _ = try await client.air(for: Coordinate(latitude: 59.91391, longitude: 10.75221))
        _ = try await client.air(for: Coordinate(latitude: 59.91391, longitude: 10.75221))
        #expect(transport.requests.count == 1)
        let url = try #require(transport.requests.first?.url?.absoluteString)
        #expect(url.contains("latitude=59.91&longitude=10.75"))
        #expect(transport.requests.first?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Skyline/") == true)
    }
}

@Suite struct ConditionsTests {
    private func forecast(_ tweak: (inout Hour, Int) -> Void = { _, _ in }) -> Forecast {
        Fixture.forecast((0..<24).map { i in
            var h = Hour(); h.temperature = 15; h.wind = 3
            h.instant = ["apparent_air_temperature": 15, "ultraviolet_index_clear_sky": 1, "cloud_area_fraction": 20]
            h.details = ["probability_of_precipitation": 5]
            tweak(&h, i)
            return h
        })
    }

    @Test func aQuietDayShowsLittle() {
        let c = Conditions(forecast: forecast(), now: afternoon, timeZone: oslo, air: air(15), scale: .european)
        #expect(c.chips.map(\.id) == ["air", "sun"])
        #expect(c.chips.first?.text == "Air good")
        #expect(c.urgency == .none)
        #expect(c.note == "air good")
        #expect(c.tiles.map(\.id).starts(with: ["feels", "wind", "rain", "air"]))
    }

    @Test func windFeelsLikeAndRainShowUp() {
        let f = forecast { h, i in
            if i == 0 { h.wind = 7; h.instant["wind_speed_of_gust"] = 13; h.instant["apparent_air_temperature"] = 11 }
            if i == 2 { h.details["probability_of_precipitation"] = 70 }
        }
        let c = Conditions(forecast: f, now: afternoon, timeZone: oslo, air: nil, scale: .european)
        #expect(c.chips.map(\.text).prefix(3) == ["Feels 11°", "Wind 7", "Rain 70%"])
        #expect(c.chips[1].detail == "gusts 13 m/s")
        #expect(c.chips[2].detail == "at 18:00")
    }

    @Test func veryPoorAirIsANotice() {
        let c = Conditions(forecast: forecast(), now: afternoon, timeZone: oslo, air: air(85), scale: .european)
        let chip = c.chips.first { $0.id == "air" }
        #expect(chip?.tone == .warn && chip?.text == "Air very poor")
        #expect(c.urgency == .notice)
    }

    @Test func strongUVUnderAClearSkyIsANotice() {
        let f = forecast { h, i in if i == 0 { h.instant["ultraviolet_index_clear_sky"] = 8.4 } }
        let c = Conditions(forecast: f, now: afternoon, timeZone: oslo, air: nil, scale: .european)
        #expect(c.chips.contains { $0.id == "uv" && $0.tone == .warn && $0.text == "UV up to 8" })
        #expect(c.urgency == .notice)
    }

    @Test func strongUVUnderCloudIsNot() {
        let f = forecast { h, i in
            h.instant["cloud_area_fraction"] = 95
            if i == 0 { h.instant["ultraviolet_index_clear_sky"] = 8.4 }
        }
        let c = Conditions(forecast: f, now: afternoon, timeZone: oslo, air: nil, scale: .european)
        #expect(c.urgency == .none)
    }

    @Test func pollenInEurope() {
        let c = Conditions(forecast: forecast(), now: afternoon, timeZone: oslo, air: air(15, pollen: [.birch: 150, .grass: 2]),
                           scale: .european)
        #expect(c.chips.contains { $0.text == "Birch pollen high" && $0.tone == .warn })
        #expect(c.tiles.contains { $0.id == "pollen" && $0.value == "High" })
    }

    @Test func compass() {
        #expect(Conditions.compass(210) == "SW")
        #expect(Conditions.compass(359) == "N")
        #expect(Conditions.compass(-45) == "NW")
    }
}

@Suite struct IslandNoteTests {
    @Test func dryDayCarriesTheNote() throws {
        let f = Fixture.forecast(Fixture.dry())
        let report = try #require(SkyReport(forecast: f, now: afternoon, timeZone: oslo))
        let page = IslandPage(report: report, outlook: HourlyOutlook(forecast: f, now: afternoon), urgency: .none,
                              timeZone: oslo, note: "air good · UV up to 3")
        #expect(page.subtitle == "Dry for 12 hours · air good · UV up to 3")
    }
}

private extension Date {
    /// This clock time (parsed on 1 Jan 2000) moved onto the local day of `day`.
    func onDay(of day: Date, _ zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let t = cal.dateComponents([.hour, .minute], from: self)
        return cal.date(bySettingHour: t.hour!, minute: t.minute!, second: 0, of: day)!
    }
}

@Suite struct DayDetailTests {
    @Test func daysCarryWindHumidityChanceAndUV() throws {
        let hours: [Fixture.Hour] = (0..<30).map { i in
            var h = Fixture.Hour(); h.wind = Double(i % 7)
            h.instant = ["wind_speed_of_gust": Double(i % 7) + 4, "ultraviolet_index_clear_sky": i == 2 ? 4.2 : 1]
            h.details = ["probability_of_precipitation": i == 3 ? 60 : 10]
            return h
        }
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        let report = try #require(SkyReport(forecast: Fixture.forecast(hours), now: Fixture.t0, timeZone: oslo, dayCount: 7))
        let today = try #require(report.days.first)
        #expect(today.wind == 6 && today.gust == 10)
        #expect(today.precipitationChance == 60)
        #expect(today.uv == 4.2)
        #expect(abs((today.humidity ?? 0) - 71.2) < 0.01)
        #expect(report.days.count == 2)
    }
}

@Suite struct CloudWeatherTests {
    private let oslo = TimeZone(identifier: "Europe/Oslo")!

    private func report(_ tweak: (inout Fixture.Hour, Int) -> Void, at now: Date = Fixture.t0.addingTimeInterval(20 * 60)) throws -> SkyReport {
        let hours: [Fixture.Hour] = (0..<24).map { i in var h = Fixture.Hour(); tweak(&h, i); return h }
        return try #require(SkyReport(forecast: Fixture.forecast(hours), now: now, timeZone: oslo))
    }

    @Test func rainNowScalesWithTheRate() throws {
        let r = try report { h, i in if i < 2 { h.symbol = "heavyrain"; h.precipitation = 4 } }
        #expect(r.cloudWeather == .rain(1))
        let light = try report { h, i in if i < 2 { h.symbol = "lightrain"; h.precipitation = 0.4 } }
        #expect(light.cloudWeather == .rain(0.15))
    }

    @Test func thunderWins() throws {
        let r = try report { h, i in if i == 1 { h.symbol = "rainandthunder"; h.precipitation = 2 } }
        #expect(r.cloudWeather == .thunder)
    }

    @Test func snowFallingIsSnow() throws {
        let r = try report { h, i in if i == 0 { h.symbol = "snow"; h.precipitation = 1 } }
        #expect(r.cloudWeather == .snow)
    }

    @Test func clearByDayIsTheSun() throws {
        #expect(try report { h, _ in h.symbol = "clearsky_day" }.cloudWeather == .clear)
        #expect(try report { h, _ in h.symbol = "fair_day" }.cloudWeather == .partlyCloudy)
        #expect(try report { h, _ in h.symbol = "cloudy" }.cloudWeather == .none)
    }

    @Test func clearNightIsTheMoon() throws {
        let night = Fixture.t0.addingTimeInterval(8 * 3600)
        #expect(try report({ h, _ in h.symbol = "clearsky_night" }, at: night).cloudWeather == .clearNight)
    }

    @Test func windAndHeat() throws {
        #expect(try report { h, _ in h.wind = 12 }.cloudWeather == .wind)
        #expect(try report { h, _ in h.temperature = 32; h.symbol = "clearsky_day" }.cloudWeather == .hot)
    }
}
