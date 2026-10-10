import Foundation
import NimbiKit
import Testing
@testable import SkylineCore

private typealias Hour = Fixture.Hour

private func rain(_ mm: Double) -> Hour {
    var h = Hour(); h.symbol = mm >= 1 ? "rain" : "lightrain"; h.precipitation = mm; return h
}

/// 14:20 UTC on the fixture day; Oslo's sun is still up (sunset around 16:40 UTC).
private let afternoon = Fixture.t0.addingTimeInterval(20 * 60)
private let oslo = TimeZone(identifier: "Europe/Oslo")!

@Suite struct SkyReportTests {
    @Test func dryDay() throws {
        let report = try #require(SkyReport(forecast: Fixture.forecast(Fixture.dry()), now: afternoon, timeZone: oslo))
        #expect(report.rain == .dry)
        #expect(report.hazards.isEmpty)
        #expect(report.current.time == Fixture.t0)
    }

    @Test func rainWithinTheHour() throws {
        var hours = Fixture.dry(); hours[1] = rain(0.4); hours[2] = rain(1.2)
        let report = try #require(SkyReport(forecast: Fixture.forecast(hours), now: afternoon, timeZone: oslo))
        #expect(report.rain == .soon(at: Fixture.t0.addingTimeInterval(3600), peak: 1.2))
    }

    @Test func rainLaterIsNotSoon() throws {
        var hours = Fixture.dry(); hours[4] = rain(0.5)
        let report = try #require(SkyReport(forecast: Fixture.forecast(hours), now: afternoon, timeZone: oslo))
        #expect(report.rain == .later(at: Fixture.t0.addingTimeInterval(4 * 3600), peak: 0.5))
    }

    @Test func rainingNowRunsToTheEndOfTheWetSpell() throws {
        var hours = Fixture.dry(); hours[0] = rain(0.3); hours[1] = rain(2); hours[2] = rain(0.2)
        let report = try #require(SkyReport(forecast: Fixture.forecast(hours), now: afternoon, timeZone: oslo))
        #expect(report.rain == .now(until: Fixture.t0.addingTimeInterval(3 * 3600), peak: 2))
    }

    @Test func rainBeyondTwelveHoursIsDry() throws {
        var hours = Fixture.dry(); hours[13] = rain(3)
        let report = try #require(SkyReport(forecast: Fixture.forecast(hours), now: afternoon, timeZone: oslo))
        #expect(report.rain == .dry)
    }

    @Test func findsHazardsInTheNextThreeHours() throws {
        var hours = Fixture.dry()
        hours[2].symbol = "heavyrainandthunder"
        hours[1].wind = 22
        hours[6].temperature = 36 // too far ahead to count
        let report = try #require(SkyReport(forecast: Fixture.forecast(hours), now: afternoon, timeZone: oslo))
        #expect(report.hazards == [.storm(at: Fixture.t0.addingTimeInterval(3600), windSpeed: 22),
                                   .thunder(at: Fixture.t0.addingTimeInterval(2 * 3600))])
    }

    @Test func groupsLocalDays() throws {
        var hours = Fixture.dry(48)
        for i in hours.indices { hours[i].temperature = Double(i % 24) }
        hours[20] = rain(1.5) // 10:00 local on day two
        let report = try #require(SkyReport(forecast: Fixture.forecast(hours), now: afternoon, timeZone: oslo))
        // Today (local) runs 16:00…23:00 local = steps 0…7.
        #expect(report.days.count == 3)
        #expect(report.days[0].low == 0)
        #expect(report.days[0].high == 7)
        #expect(report.days[1].precipitation == 1.5)
        #expect(report.days[1].symbol?.base == "rain")
    }

    @Test func nothingAheadGivesNoReport() {
        #expect(SkyReport(forecast: Fixture.forecast(Fixture.dry(2)), now: Fixture.t0.addingTimeInterval(3 * 3600)) == nil)
    }
}

@Suite struct SunTests {
    @Test func juneSolsticeNoonAtTheEquator() {
        // 2024-06-21 12:00 UTC at 0°, 0°: the sun stands 90 − 23.44 ≈ 66.6° high.
        let elevation = Sun.elevation(at: Date(timeIntervalSince1970: 1_718_971_200), coordinate: Coordinate(latitude: 0, longitude: 0))
        #expect(abs(elevation - 66.5) < 0.5)
    }

    @Test func osloDayAndNight() {
        #expect(Sun.isUp(at: afternoon, coordinate: Fixture.oslo))
        #expect(!Sun.isUp(at: Fixture.t0.addingTimeInterval(8 * 3600), coordinate: Fixture.oslo))
    }

    @Test func midnightSunInTromso() {
        // 21 June 2026, 23:00 UTC (01:00 local): the sun stays up north of the Arctic Circle.
        let tromso = Coordinate(latitude: 69.6492, longitude: 18.9553)
        #expect(Sun.isUp(at: Date(timeIntervalSince1970: 1_782_082_800), coordinate: tromso))
    }
}

@Suite struct SkyMoodTests {
    private func report(_ hours: [Hour], at now: Date = afternoon) -> SkyReport {
        SkyReport(forecast: Fixture.forecast(hours), now: now, timeZone: oslo)!
    }

    @Test func clearDayIsRelaxed() {
        #expect(SkyMood.from(report(Fixture.dry()), dataAge: 600) == SkyMood(mood: .relaxed))
    }

    @Test func rainSoonIsABusyNotice() {
        var hours = Fixture.dry(); hours[1] = rain(1.2)
        #expect(SkyMood.from(report(hours), dataAge: 600) == SkyMood(mood: .busy, urgency: .notice, working: 3))
    }

    @Test func rainNowIsBusyButQuiet() {
        var hours = Fixture.dry(); hours[0] = rain(0.2)
        #expect(SkyMood.from(report(hours), dataAge: 600) == SkyMood(mood: .busy, urgency: .none, working: 1))
    }

    @Test func stormNeedsYou() {
        var hours = Fixture.dry(); hours[1] = rain(1); hours[2].symbol = "rainandthunder"
        #expect(SkyMood.from(report(hours), dataAge: 600) == SkyMood(mood: .asking, urgency: .needsYou))
    }

    @Test func hotDayOverheats() {
        var hours = Fixture.dry(); hours[0].temperature = 31
        #expect(SkyMood.from(report(hours), dataAge: 600).mood == .overheated)
    }

    @Test func nightSleeps() {
        let night = Fixture.t0.addingTimeInterval(8 * 3600)
        #expect(SkyMood.from(report(Fixture.dry(), at: night), dataAge: 600).mood == .asleep)
    }

    @Test func rainSoonBeatsNight() {
        var hours = Fixture.dry(); hours[9] = rain(0.6)
        let night = Fixture.t0.addingTimeInterval(8 * 3600 + 20 * 60)
        #expect(SkyMood.from(report(hours, at: night), dataAge: 600).urgency == .notice)
    }

    @Test func staleDataIsLonely() {
        var hours = Fixture.dry(); hours[1] = rain(1)
        #expect(SkyMood.from(report(hours), dataAge: 4 * 3600) == SkyMood(mood: .lonely))
        #expect(SkyMood.from(nil, dataAge: 0) == SkyMood(mood: .lonely))
    }

    @Test func livelinessIsCapped() {
        #expect(SkyMood.liveliness(0.1) == 1)
        #expect(SkyMood.liveliness(1.2) == 3)
        #expect(SkyMood.liveliness(40) == 8)
    }

    @Test func rainStoppingIsBrieflyHappy() {
        var tracker = SkyMoodTracker()
        var wet = Fixture.dry(); wet[0] = rain(0.5)
        #expect(tracker.update(report(wet), dataAge: 0, now: afternoon).mood == .busy)
        let dried = report(Fixture.dry())
        #expect(tracker.update(dried, dataAge: 0, now: afternoon).mood == .happy)
        #expect(tracker.update(dried, dataAge: 0, now: afternoon.addingTimeInterval(2)).mood == .happy)
        #expect(tracker.update(dried, dataAge: 0, now: afternoon.addingTimeInterval(4)).mood == .relaxed)
    }

    @Test func urgencyOrder() {
        #expect(Urgency.none < .notice)
        #expect(Urgency.notice < .needsYou)
    }
}
