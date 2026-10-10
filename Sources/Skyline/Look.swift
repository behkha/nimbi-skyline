import AppKit
import NimbiKit
import SkylineCore
import SwiftUI

/// SwiftUI's `@State` and `@FocusState` are macros in this SDK and their plugin only ships with
/// full Xcode. The property wrappers through an alias build with the Command Line Tools alone.
typealias ViewState<Value> = SwiftUI.State<Value>
typealias ViewFocus<Value: Hashable> = SwiftUI.FocusState<Value>

extension Color {
    /// Rain in the chart and the island bars: `sky` from the aurora as a flat color, never the
    /// gradient. Skyline's own token until DESIGN.md 4.5 and NimbiKit gain `Nimbi.State.rain`.
    static let rain = Color(hex: "#7FD0FF")
}

/// Skyline's look settings: saved here, mirrored into NimbiKit's `NimbiAppearance`.
enum LookSettings {
    private static let themeKey = "Theme"
    private static let textScaleKey = "TextScale"
    static let textScales: [Double] = [0.9, 1, 1.1, 1.25]

    static func load(_ defaults: UserDefaults = .standard) {
        let look = NimbiAppearance.shared
        look.theme = defaults.string(forKey: themeKey).flatMap(NimbiTheme.init(rawValue:)) ?? .dark
        let scale = defaults.double(forKey: textScaleKey)
        look.textScale = textScales.contains(scale) ? scale : 1
        // Skyline lives in the menu bar; panels never hang from the notch (DESIGN.md 18.2).
        look.dock = .right
    }

    static func setTheme(_ theme: NimbiTheme, _ defaults: UserDefaults = .standard) {
        NimbiAppearance.shared.theme = theme
        defaults.set(theme.rawValue, forKey: themeKey)
    }

    static func setTextScale(_ scale: Double, _ defaults: UserDefaults = .standard) {
        NimbiAppearance.shared.textScale = scale
        defaults.set(scale, forKey: textScaleKey)
    }
}

extension WeatherSymbol {
    /// The SF Symbol for this code, night variants included.
    var systemImage: String {
        let night = variant == .night
        if isThunder { return "cloud.bolt.rain" }
        if isSnow { return "cloud.snow" }
        if isSleet { return "cloud.sleet" }
        if base.hasPrefix("heavyrain") { return "cloud.heavyrain" }
        if base.contains("showers") { return night ? "cloud.moon.rain" : "cloud.sun.rain" }
        if base.hasPrefix("lightrain") { return "cloud.drizzle" }
        if isPrecipitation { return "cloud.rain" }
        switch base {
        case "clearsky": return night ? "moon.stars" : variant == .polartwilight ? "sun.horizon" : "sun.max"
        case "fair", "partlycloudy": return night ? "cloud.moon" : "cloud.sun"
        case "fog": return "cloud.fog"
        default: return "cloud"
        }
    }
}

enum Clock {
    /// "14:12" in the place's own time zone.
    static func time(_ date: Date, in timeZone: TimeZone) -> String {
        formatter("HH:mm", timeZone).string(from: date)
    }

    /// "14:12" today, "Fri 14:12" on another day.
    static func moment(_ date: Date, in timeZone: TimeZone, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let format = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return formatter(format, timeZone).string(from: date)
    }

    static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}
