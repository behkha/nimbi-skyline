import Foundation
import SkylineCore

enum FetchCommand {
    static func run(_ coordinate: Coordinate) async {
        let client = METClient(configuration: .current())
        do {
            let result = try await client.forecast(for: coordinate)
            let now = Date()
            print("source   \(result.source) via \(client.configuration.baseURL.absoluteString)")
            print("expires  \(result.expires) (fetched \(result.fetchedAt))")
            guard let report = SkyReport(forecast: result.forecast, now: now) else {
                print("no steps ahead of now")
                return
            }
            let c = report.current
            print("now      \(c.temperature)°  \(c.symbol?.code ?? "–")  wind \(c.windSpeed ?? 0) m/s")
            print("rain     \(report.rain)")
            print("hazards  \(report.hazards.isEmpty ? "none" : "\(report.hazards)")")
            print("night    \(report.isNight)")
            let mood = SkyMood.from(report, dataAge: now.timeIntervalSince(result.fetchedAt))
            print("mood     \(mood.mood) · urgency \(mood.urgency) · working \(mood.working)")
            let day = DateFormatter()
            day.dateFormat = "EEE d"
            for d in report.days {
                print("  \(day.string(from: d.date))  \(Int(d.low.rounded()))–\(Int(d.high.rounded()))°  \(d.precipitation) mm  \(d.symbol?.code ?? "–")")
            }
            print("Weather data © MET Norway (CC BY 4.0)")
        } catch {
            print("error: \(error)")
        }
    }
}
