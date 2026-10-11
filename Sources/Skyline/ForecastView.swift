import NimbiKit
import SkylineCore
import SwiftUI

/// The dropdown's main page, option A of docs/redesign-options.html: two panes, 600 wide.
/// Left, the now card (big temperature, high and low, the condition in big capitals, sun times
/// and facts); right, the place and time, seven day cards, the 24 h skyline chart, the keys and
/// MET's credit. Clicking a day (or ← →) shows that day in the now card. nimbi's cloud peeks in
/// from the bottom-right corner.
struct ForecastView: View {
    @ObservedObject var model: SkyModel
    @ObservedObject var location: LocationService
    @ObservedObject var panel: PanelState
    var actions: PanelActions
    @ObservedObject private var look = NimbiAppearance.shared

    private var k: CGFloat { look.textScale }

    var body: some View {
        Group {
            if let report = model.report {
                HStack(alignment: .top, spacing: 12 * k) {
                    NowCard(model: model, report: report, day: selected(report), style: panel.conditionsStyle)
                        .frame(width: 252 * k)
                    VStack(alignment: .leading, spacing: 10 * k) {
                        topline
                        DayCards(days: report.days, timeZone: model.timeZone, selection: $panel.selectedDay)
                        SkylineChart(outlook: model.outlook, timeZone: model.timeZone, height: 100)
                        keys
                        footer
                    }
                }
                .padding(12 * k)
                .frame(width: 600 * k)
            } else {
                waiting
            }
        }
        .overlay(alignment: .bottomTrailing) { peekingCloud }
    }

    private func selected(_ report: SkyReport) -> SkyReport.Day? {
        panel.selectedDay > 0 && panel.selectedDay < report.days.count ? report.days[panel.selectedDay] : nil
    }

    /// The cloud, big and cropped by the panel's corner, in the sky's mood, eyes on the cursor.
    private var peekingCloud: some View {
        let size = (model.report == nil ? 100 : 124) * k
        return NimbiCloud(size: size, mood: model.mood.mood, working: model.mood.working)
            .frame(width: size, height: size)
            .offset(x: size * 0.26, y: size * 0.34)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Right pane

    private var topline: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline) {
                Text(model.place?.name.uppercased() ?? "")
                    .font(look.font(12.5, .semibold))
                    .tracking(1)
                    .foregroundStyle(Nimbi.Text.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                (Text(Clock.formatter("EEE d MMM, ", model.timeZone).string(from: context.date))
                    .foregroundColor(Nimbi.Text.dim)
                 + Text(Clock.time(context.date, in: model.timeZone)).foregroundColor(Nimbi.Text.primary).bold())
                    .font(look.font(11.5))
                    .monospacedDigit()
            }
            .padding(.horizontal, 4 * k)
            .padding(.top, 2 * k)
            .accessibilityElement(children: .combine)
        }
    }

    private var keys: some View {
        HStack(spacing: 6) {
            if model.canRefresh {
                key("Refresh", "R", help: "Ask MET again · R", action: actions.refresh)
            }
            key("Place", "L", help: "Change place · L", action: actions.choosePlace)
            key(panel.conditionsStyle == .strip ? "More" : "Less", "D",
                help: panel.conditionsStyle == .strip ? "Every detail · D" : "Only what matters · D",
                action: actions.toggleDetails)
            Button(action: actions.openSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                    KeyHint(key: ",")
                }
            }
            .buttonStyle(PillButtonStyle(hint: true))
            .focusable(false)
            .help("Settings · ,")
            .accessibilityLabel("Settings")
            Spacer(minLength: 0)
        }
        .padding(.trailing, 78 * k)   // room for the cloud
    }

    private func key(_ title: String, _ key: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                KeyHint(key: key)
            }
        }
        .buttonStyle(PillButtonStyle(hint: true))
        .focusable(false)
        .help(help)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Link("Weather data © MET Norway", destination: URL(string: "https://www.met.no/en")!)
                .foregroundStyle(Nimbi.Text.dim)
                .help("MET Norway's Locationforecast, CC BY 4.0")
                .focusable(false)
            if model.air != nil {
                Link("Air quality © CAMS via Open-Meteo", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                    .foregroundStyle(Nimbi.Text.dim)
                    .help("Copernicus Atmosphere Monitoring Service data through Open-Meteo.com, CC BY 4.0")
                    .focusable(false)
            }
        }
        .font(look.font(10))
        .padding(.horizontal, 4 * k)
        .padding(.trailing, 100 * k)
    }

    // MARK: Before there's a forecast

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(look.font(15, .semibold))
                .foregroundStyle(Nimbi.Text.primary)
            Text(subtitle)
                .font(look.font(12))
                .foregroundStyle(Nimbi.Text.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                key("Place", "L", help: "Change place · L", action: actions.choosePlace)
                key("Settings", ",", help: "Settings · ,", action: actions.openSettings)
            }
            .padding(.top, 4)
            Text("Weather data © MET Norway")
                .font(look.font(10))
                .foregroundStyle(Nimbi.Text.faint)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .padding(.trailing, 70 * k)
        .frame(width: 318 * k, alignment: .leading)
        .frame(minHeight: 150 * k, alignment: .top)
    }

    private var title: String {
        if let place = model.place { return place.name }
        switch location.status {
        case .needsCity: return "No place yet."
        case .locating, .ready: return "Looking for you…"
        }
    }

    private var subtitle: String {
        if model.place == nil {
            return location.status == .needsCity
                ? "Location is off for Skyline. Pick a city with L."
                : "Asking your Mac where it is."
        }
        if model.failed {
            let when = model.nextRefresh.map { " Trying again at \(Clock.time($0, in: .current))." } ?? ""
            return "Can't reach the sky right now.\(when)"
        }
        return "Reading the sky…"
    }
}

// MARK: - The now card

/// Now, or the day picked on the right: big temperature, high and low, the condition in capitals,
/// sunrise and sunset, and the facts (the ones that matter, or all of them with D).
private struct NowCard: View {
    @ObservedObject var model: SkyModel
    var report: SkyReport
    /// nil for now; a day for one picked on the right.
    var day: SkyReport.Day?
    var style: ConditionsStyle
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        let k = look.textScale
        VStack(alignment: .leading, spacing: 12 * k) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayTitle)
                        .font(look.font(11.5, .semibold))
                        .foregroundStyle(Nimbi.Text.dim)
                    if let subline {
                        Text(subline)
                            .font(look.font(11.5))
                            .foregroundStyle(Nimbi.Text.dim)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6 * k)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.degrees(day?.high ?? report.current.temperature))
                        .font(.system(size: 60 * k, weight: .bold))
                        .tracking(-2)
                        .monospacedDigit()
                        .foregroundStyle(Nimbi.Text.primary)
                        .accessibilityLabel(day == nil ? "\(Int(report.current.temperature.rounded())) degrees now"
                                            : "High \(Int((day?.high ?? 0).rounded())) degrees")
                    highLow
                }
            }
            Text(condition.uppercased())
                .font(.system(size: 26 * k, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Nimbi.Text.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            sunRow
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .leading),
                                GridItem(.flexible(), spacing: 10, alignment: .leading)],
                      alignment: .leading, spacing: 10 * k) {
                ForEach(facts) { FactView(fact: $0) }
            }
            Spacer(minLength: 0)
            if day == nil, let fetchedAt = model.fetchedAt {
                Text("Updated \(Clock.moment(fetchedAt, in: .current))")
                    .font(look.font(10))
                    .foregroundStyle(Nimbi.Text.faint)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16 * k).padding(.top, 14 * k).padding(.bottom, 16 * k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Nimbi.Radius.panel, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#1D1D20"), Color(hex: "#151517")], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: Nimbi.Radius.panel, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private var dayTitle: String {
        guard let day else { return "Now" }
        return Clock.formatter("EEEE d MMM", model.timeZone).string(from: day.date)
    }

    private var condition: String {
        (day?.symbol ?? report.current.symbol)?.phrase ?? "No word on the sky"
    }

    /// What the condition alone doesn't say: "Rain from 21:00", or nothing.
    private var subline: String? {
        guard day == nil else { return nil }
        let headline = report.headline(timeZone: model.timeZone)
        let phrase = condition
        if headline == phrase { return nil }
        if headline.hasPrefix(phrase + " · ") {
            let rest = headline.dropFirst(phrase.count + 3)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return headline
    }

    private var highLow: some View {
        let today = report.days.first
        let high = day?.high ?? today?.high, low = day?.low ?? today?.low
        let feels = day == nil ? report.current.apparentTemperature : nil
        return HStack(spacing: 8) {
            if let high { Text("H \(Self.degrees(high))") }
            if let low { Text("L \(Self.degrees(low))") }
            if let feels, abs(feels - report.current.temperature) >= 2 { Text("Feels \(Self.degrees(feels))") }
        }
        .font(look.font(11.5))
        .foregroundStyle(Nimbi.Text.dim)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }

    private var sunRow: some View {
        let times = model.place.map { Sun.times(on: day?.date ?? Date(), coordinate: $0.coordinate, timeZone: model.timeZone) }
        return HStack(spacing: 18) {
            sun("sunrise", times?.rise, label: "Sunrise")
            sun("sunset", times?.set, label: "Sunset")
        }
    }

    private func sun(_ icon: String, _ time: Date?, label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon + ".fill")
                .symbolRenderingMode(.multicolor)
                .font(look.font(14, .medium))
            Text(time.map { Clock.time($0, in: model.timeZone) } ?? "–")
                .font(look.font(12.5, .medium))
                .foregroundStyle(Nimbi.Text.strong)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(time.map { Clock.time($0, in: model.timeZone) } ?? "none")")
    }

    /// Now: wind, humidity, air and UV plus anything amber (the strip's spirit), or every tile
    /// with D. A picked day: what the forecast knows about it.
    private var facts: [Fact] {
        if let day {
            var list: [Fact] = []
            if let wind = day.wind {
                list.append(Fact(id: "wind", icon: "wind", label: "Wind", value: "up to \(Int(wind.rounded())) m/s",
                                 detail: day.gust.map { "gusts \(Int($0.rounded()))" } ?? ""))
            }
            if let humidity = day.humidity {
                list.append(Fact(id: "humidity", icon: "humidity", label: "Humidity", value: "\(Int(humidity.rounded()))%",
                                 detail: "on average"))
            }
            list.append(Fact(id: "rain", icon: "umbrella", label: "Rain",
                             value: day.precipitation > 0 ? String(format: "%.1f mm", day.precipitation) : "Dry",
                             detail: day.precipitationChance.map { "\(Int($0.rounded()))% chance" } ?? ""))
            if let uv = day.uv, uv >= 1 {
                list.append(Fact(id: "uv", icon: "sun.max", label: "UV", value: "up to \(Int(uv.rounded()))",
                                 detail: "clear sky", warn: uv >= Conditions.strongUV))
            }
            return list
        }
        let tiles = model.conditions.tiles.filter { $0.id != "sun" }
        let shown: [Conditions.Tile]
        switch style {
        case .grid: shown = tiles
        case .strip:
            let core: Set<String> = ["wind", "humidity", "air", "uv"]
            shown = tiles.filter { core.contains($0.id) || $0.tone == .warn }
        }
        return shown.map {
            Fact(id: $0.id, icon: Self.icon[$0.id] ?? "circle", label: $0.label, value: $0.value,
                 detail: $0.meaning, warn: $0.tone == .warn)
        }
    }

    static let icon = ["feels": "thermometer.medium", "wind": "wind", "rain": "umbrella", "thunder": "cloud.bolt",
                       "fog": "cloud.fog", "air": "aqi.medium", "uv": "sun.max", "pollen": "leaf",
                       "humidity": "humidity", "pressure": "gauge", "clouds": "cloud"]

    static func degrees(_ t: Double) -> String { "\(Int(t.rounded()))°" }
}

private struct Fact: Identifiable {
    var id: String
    var icon: String
    var label: String
    var value: String
    var detail: String
    var warn = false
}

private struct FactView: View {
    var fact: Fact
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: fact.icon)
                .font(look.font(15))
                .foregroundStyle(fact.warn ? Nimbi.State.waiting : Nimbi.Text.strong)
                .frame(width: 20 * look.textScale)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(fact.label.uppercased())
                    .font(look.font(10, .bold))
                    .tracking(0.6)
                    .foregroundStyle(Nimbi.Text.strong)
                Text(fact.value)
                    .font(look.font(12, .medium))
                    .foregroundStyle(fact.warn ? Color(hex: "#FFD27A") : Nimbi.Text.message)
                    .monospacedDigit()
                    .lineLimit(1)
                if !fact.detail.isEmpty {
                    Text(fact.detail)
                        .font(look.font(10.5))
                        .foregroundStyle(Nimbi.Text.dim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fact.label): \(fact.value)\(fact.detail.isEmpty ? "" : ", \(fact.detail)")")
    }
}

// MARK: - Day cards

/// Seven days, four to a row, in multicolor SF Symbols. The picked one sits in a raised tile;
/// clicking it again goes back to now.
private struct DayCards: View {
    var days: [SkyReport.Day]
    var timeZone: TimeZone
    @Binding var selection: Int
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Button {
                    withAnimation(Nimbi.Motion.swap) { selection = selection == index ? 0 : index }
                } label: {
                    card(day, index: index)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }

    private func card(_ day: SkyReport.Day, index: Int) -> some View {
        let on = index == selection
        return VStack(spacing: 2) {
            Image(systemName: day.symbol?.filledImage ?? "cloud.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 22 * look.textScale))
                .frame(height: 28 * look.textScale)
            Text(index == 0 ? "Today" : Clock.formatter("EEE", timeZone).string(from: day.date))
                .font(look.font(13, .semibold))
                .foregroundStyle(Nimbi.Text.primary)
                .padding(.top, 2)
            Text("\(Int(day.high.rounded()))°")
                .font(look.font(11))
                .foregroundStyle(Nimbi.Text.strong)
            Text("\(Int(day.low.rounded()))°")
                .font(look.font(11))
                .foregroundStyle(Nimbi.Text.dim)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(on ? Color(hex: "#1E1E21") : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(on ? 0.1 : 0), lineWidth: 1))
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(day, index: index))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func spoken(_ day: SkyReport.Day, index: Int) -> String {
        let name = index == 0 ? "Today" : Clock.formatter("EEEE", timeZone).string(from: day.date)
        let sky = day.symbol.map { ", \($0.phrase.lowercased())" } ?? ""
        return "\(name): high \(Int(day.high.rounded()))°, low \(Int(day.low.rounded()))°\(sky)"
    }
}
