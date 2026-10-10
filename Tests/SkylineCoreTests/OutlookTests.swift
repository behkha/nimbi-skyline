import Foundation
import Testing
@testable import SkylineCore

private typealias Hour = Fixture.Hour

private let afternoon = Fixture.t0.addingTimeInterval(20 * 60)
private let oslo = TimeZone(identifier: "Europe/Oslo")!

private func hours(_ temps: [Double], rain: [Int: Double] = [:]) -> [Hour] {
    temps.enumerated().map { i, t in
        var h = Hour(); h.temperature = t
        if let mm = rain[i] { h.precipitation = mm; h.symbol = "lightrain" }
        return h
    }
}

@Suite struct HourlyOutlookTests {
    @Test func startsAtTheHourCoveringNow() {
        let outlook = HourlyOutlook(forecast: Fixture.forecast(Fixture.dry(30)), now: afternoon)
        #expect(outlook.hours.count == 24)
        #expect(outlook.hours.first?.time == Fixture.t0)
    }

    @Test func leavesOutSixHourlySteps() throws {
        let data = Fixture.json(hours: Fixture.dry(5), sixHourly: 4)
        let outlook = HourlyOutlook(forecast: try Forecast.decodeMET(data), now: afternoon)
        #expect(outlook.hours.count == 5)
    }

    @Test func summaryNamesHighLowAndRain() {
        // 16:00 local is 14:00 UTC (CEST).
        let forecast = Fixture.forecast(hours([18, 17, 16, 12, 10, 11], rain: [1: 0.4, 2: 1.2]))
        let text = HourlyOutlook(forecast: forecast, now: afternoon, count: 6).summary(timeZone: oslo)
        #expect(text == "Next 6 hours: 18° now, low 10° at 20:00. Rain 17:00–19:00, 1.6 mm in all, heaviest 1.2 mm at 18:00.")
    }

    @Test func summarySaysWhenItStaysDry() {
        let forecast = Fixture.forecast(hours([12, 13, 14]))
        let text = HourlyOutlook(forecast: forecast, now: afternoon).summary(timeZone: oslo)
        #expect(text == "Next 3 hours: 12° now, high 14° at 18:00. No rain.")
    }

    @Test func emptyOutlook() {
        #expect(HourlyOutlook(hours: []).summary(timeZone: oslo) == "No hourly forecast yet.")
    }
}

@Suite struct HeadlineTests {
    @Test func symbolPhrases() {
        #expect(WeatherSymbol("clearsky_day").phrase == "Clear sky")
        #expect(WeatherSymbol("partlycloudy_night").phrase == "Partly cloudy")
        #expect(WeatherSymbol("lightrainshowersandthunder_day").phrase == "Light rain showers and thunder")
        #expect(WeatherSymbol("heavysleet").phrase == "Heavy sleet")
        #expect(WeatherSymbol("somethingnew").phrase == "somethingnew")
    }

    @Test func rainSoonWins() throws {
        let forecast = Fixture.forecast(hours([18, 17, 16], rain: [1: 0.4]))
        let report = try #require(SkyReport(forecast: forecast, now: afternoon, timeZone: oslo))
        #expect(report.headline(timeZone: oslo) == "Rain within the hour")
    }

    @Test func rainingNowSaysUntilWhen() throws {
        let forecast = Fixture.forecast(hours([18, 17, 16, 15], rain: [0: 0.4, 1: 0.8]))
        let report = try #require(SkyReport(forecast: forecast, now: afternoon, timeZone: oslo))
        #expect(report.headline(timeZone: oslo) == "Light rain until 18:00")
    }

    @Test func laterRainFollowsTheCondition() throws {
        let forecast = Fixture.forecast(hours([18, 17, 16, 15, 14], rain: [4: 0.4]))
        let report = try #require(SkyReport(forecast: forecast, now: afternoon, timeZone: oslo))
        #expect(report.headline(timeZone: oslo) == "Cloudy · rain from 20:00")
    }

    @Test func hazardsComeFirst() throws {
        var h = hours([18, 18, 18]); h[1].symbol = "rainandthunder"; h[1].precipitation = 2
        let report = try #require(SkyReport(forecast: Fixture.forecast(h), now: afternoon, timeZone: oslo))
        #expect(report.headline(timeZone: oslo) == "Thunder from 17:00")
    }

    @Test func plainCondition() throws {
        let report = try #require(SkyReport(forecast: Fixture.forecast(Fixture.dry()), now: afternoon, timeZone: oslo))
        #expect(report.headline(timeZone: oslo) == "Cloudy")
    }
}
