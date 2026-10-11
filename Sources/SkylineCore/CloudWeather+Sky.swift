import Foundation
import NimbiKit

extension WeatherSymbol {
    /// The props around the cloud for this symbol alone (no rain rate, wind or heat).
    public func cloudWeather(isNight: Bool) -> CloudWeather {
        if isThunder { return .thunder }
        if isSleet { return .sleet }
        if isSnow { return .snow }
        if isPrecipitation { return .rain(base.hasPrefix("heavy") ? 0.9 : base.hasPrefix("light") ? 0.25 : 0.55) }
        switch base {
        case "fog": return .fog
        case "clearsky": return isNight ? .clearNight : .clear
        case "fair": return isNight ? .clearNight : .partlyCloudy
        case "partlycloudy": return isNight ? .none : .partlyCloudy
        default: return .none
        }
    }
}

extension SkyReport {
    /// What the cloud wears right now: the weather around it (docs/design-choices.md, "The cloud
    /// and the weather"). Thunder first, then what's falling, heat, fog, wind, then the sky.
    public var cloudWeather: CloudWeather {
        let symbol = current.symbol
        if symbol?.isThunder == true || hazards.contains(where: { if case .thunder = $0 { return true }; return false }) {
            return .thunder
        }
        if case .now(_, let peak) = rain {
            if symbol?.isSnow == true { return .snow }
            if symbol?.isSleet == true { return .sleet }
            return .rain(min(1, max(0.15, peak / 4)))
        }
        if isHot, !isNight { return .hot }
        if symbol?.base == "fog" || (current.fog ?? 0) >= 50 { return .fog }
        if (current.windSpeed ?? 0) >= 10 || (current.windGust ?? 0) >= 17 { return .wind }
        return symbol?.cloudWeather(isNight: isNight) ?? .none
    }
}

extension SkyReport.Day {
    /// The props for a day picked in the dropdown: its most notable weather, by day.
    public var cloudWeather: CloudWeather {
        if high >= SkyReport.hot, symbol?.isPrecipitation != true { return .hot }
        return symbol?.cloudWeather(isNight: false) ?? .none
    }
}
