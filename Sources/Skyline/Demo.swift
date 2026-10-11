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
            let chance = mm > 0 ? 85.0 : (sky == "rain" && i < 8 ? 40 : 5)
            let uv = max(0, 6 * sin(Double((i + 14) % 24 - 6) / 12 * .pi)) * (sky == "clear" ? 1.4 : 1)
            return ForecastStep(time: hour.addingTimeInterval(Double(i) * 3600), temperature: t,
                                windSpeed: sky == "storm" ? 9 : 4, windFromDirection: 225, humidity: 72,
                                cloudCover: sky == "clear" ? 5 : 70, symbol: WeatherSymbol(symbol), precipitation: mm)
                .with(apparentTemperature: t - (sky == "storm" ? 5 : 2), windGust: sky == "storm" ? 18 : 9,
                      dewPoint: t - 5, pressure: 1012 - Double(i) * (sky == "storm" ? 0.6 : 0.1),
                      cloudLow: 20, cloudMedium: 40, cloudHigh: 70, fog: 0, uvClearSky: uv,
                      temperatureLow: t - 1 - Double(i) / 24, temperatureHigh: t + 1 + Double(i) / 24,
                      precipitationMin: mm * 0.5, precipitationMax: mm * 1.6, precipitationChance: chance,
                      thunderChance: sky == "storm" && i < 4 ? 35 : 0)
        }
        return Forecast(coordinate: place.coordinate, updatedAt: now, steps: steps)
    }

    /// Good air and birch pollen in the rain and clear demos; very poor air in the storm one.
    static func air(now: Date = Date()) -> AirQuality? {
        guard let sky else { return nil }
        let hour = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        return AirQuality(hours: (0..<48).map { i in
            AirQuality.Hour(time: hour.addingTimeInterval(Double(i) * 3600),
                            europeanAQI: sky == "storm" ? 86 : 18, usAQI: sky == "storm" ? 165 : 26,
                            pm25: sky == "storm" ? 48 : 4, pm10: 9, ozone: 54, nitrogenDioxide: 3,
                            pollen: [.birch: sky == "rain" ? 140 : 30, .grass: 3])
        })
    }
}
