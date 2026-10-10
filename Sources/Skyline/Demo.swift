import Foundation
import SkylineCore

/// Made-up skies for checking the glyph and the dropdown without waiting for the weather:
/// `SKYLINE_DEMO=rain` (rain within the hour), `storm` (thunder, so `needsYou` and the amber
/// dot), or `clear`. Demo mode asks neither MET nor Location Services.
enum Demo {
    static let sky = ProcessInfo.processInfo.environment["SKYLINE_DEMO"]

    static var place: Place { Place(name: "Oslo", coordinate: Coordinate(latitude: 59.9139, longitude: 10.7522)) }

    static func forecast(now: Date = Date()) -> Forecast? {
        guard let sky else { return nil }
        let hour = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let temps: [Double] = [18, 18, 17, 16, 15, 15, 14, 13, 12, 12, 11, 11, 11, 10, 10, 10, 11, 12, 14, 15, 17, 18, 19, 19]
        let rain: [Double] = [0, 0.4, 1.2, 0.8, 0.3]
        let steps = (0..<120).map { i -> ForecastStep in
            let t = temps[i % temps.count] + Double(i / 24)
            var symbol = "partlycloudy_day", mm = 0.0
            switch sky {
            case "rain" where i < rain.count && rain[i] > 0: symbol = rain[i] >= 1 ? "rain" : "lightrain"; mm = rain[i]
            case "storm" where i == 1 || i == 2: symbol = "heavyrainandthunder"; mm = 3.4
            case "clear": symbol = "clearsky_day"
            default: break
            }
            return ForecastStep(time: hour.addingTimeInterval(Double(i) * 3600), temperature: t, windSpeed: 4,
                                symbol: WeatherSymbol(symbol), precipitation: mm)
        }
        return Forecast(coordinate: place.coordinate, updatedAt: now, steps: steps)
    }
}
