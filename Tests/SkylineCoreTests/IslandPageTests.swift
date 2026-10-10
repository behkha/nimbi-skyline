import Foundation
import Testing
@testable import SkylineCore

private typealias Hour = Fixture.Hour

private let afternoon = Fixture.t0.addingTimeInterval(20 * 60)
private let oslo = TimeZone(identifier: "Europe/Oslo")!

private func page(_ hours: [Hour], urgency: Urgency = .none) throws -> IslandPage {
    let forecast = Fixture.forecast(hours)
    let report = try #require(SkyReport(forecast: forecast, now: afternoon, timeZone: oslo))
    return IslandPage(report: report, outlook: HourlyOutlook(forecast: forecast, now: afternoon),
                      urgency: urgency, timeZone: oslo)
}

@Suite struct IslandPageTests {
    @Test func rainWithinTheHour() throws {
        var hours = Fixture.dry(); hours[0].temperature = 18
        hours[1].symbol = "lightrain"; hours[1].precipitation = 0.4
        hours[2].symbol = "rain"; hours[2].precipitation = 1.2
        let p = try page(hours, urgency: .notice)
        #expect(p.glance == "☂︎ 18°")
        #expect(p.title == "18° · rain within the hour")
        #expect(p.subtitle == "Rain 17:00–19:00, 1.6 mm in all")
        guard case .rain(let mm) = p.bars else { Issue.record("expected rain bars"); return }
        #expect(mm.count == 12 && mm[2] == 1.2)
        #expect(p.urgency == .notice)
    }

    @Test func dryDayShowsTemperatures() throws {
        var hours = Fixture.dry()
        for i in hours.indices { hours[i].temperature = 10 + Double(i % 6) }
        let p = try page(hours)
        #expect(p.glance == "10°")
        #expect(p.title == "10° · cloudy")
        #expect(p.subtitle == "Dry for 12 hours · high 15°, low 10°")
        guard case .temperature(let t) = p.bars else { Issue.record("expected temperature bars"); return }
        #expect(t.count == 12)
    }

    @Test func thunderLeadsTheTitle() throws {
        var hours = Fixture.dry(); hours[0].temperature = 18
        hours[1].symbol = "heavyrainandthunder"; hours[1].precipitation = 3
        let p = try page(hours, urgency: .needsYou)
        #expect(p.title == "18° · thunder from 17:00")
    }

    @Test func limitsHold() throws {
        var hours = Fixture.dry(); hours[0].symbol = "lightrainshowersandthunder"; hours[0].temperature = -12
        let p = try page(hours)
        #expect(p.glance.count <= 14)
        #expect(p.title.count <= 28)
        #expect(p.subtitle.count <= 60)
    }
}
