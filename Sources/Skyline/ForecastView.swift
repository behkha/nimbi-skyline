import NimbiKit
import SkylineCore
import SwiftUI

/// The dropdown's main page (option B): the cloud and the sky now, the 24 h skyline chart, five
/// days, and MET's credit.
struct ForecastView: View {
    @ObservedObject var model: SkyModel
    @ObservedObject var location: LocationService
    var actions: PanelActions
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let report = model.report {
                SkylineChart(outlook: model.outlook, timeZone: model.timeZone)
                if !report.days.isEmpty { days(report.days) }
            }
            keys
            footer
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(width: 318 * look.textScale)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            NimbiCloud(size: 40, mood: model.mood.mood, working: model.mood.working)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(look.font(13.5, .semibold))
                    .foregroundStyle(Nimbi.Text.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(look.font(11.5))
                    .foregroundStyle(Nimbi.Text.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let report = model.report {
                Text("\(Int(report.current.temperature.rounded()))°")
                    .font(look.font(34, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Nimbi.Text.primary)
                    .accessibilityLabel("\(Int(report.current.temperature.rounded())) degrees")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let place = model.place { return place.name }
        switch location.status {
        case .needsCity: return "No place yet."
        case .locating, .ready: return "Looking for you…"
        }
    }

    private var subtitle: String {
        if let report = model.report {
            let headline = report.headline(timeZone: model.timeZone)
            return model.mood.mood == .lonely ? "\(headline) · old news, can't reach MET" : headline
        }
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

    // MARK: Days

    private func days(_ days: [SkyReport.Day]) -> some View {
        let low = days.map(\.low).min() ?? 0
        let high = days.map(\.high).max() ?? 1
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(days.count) DAYS")
                .font(look.font(11, .semibold))
                .tracking(0.8)
                .foregroundStyle(Nimbi.Text.faint)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                DayRow(day: day, isToday: index == 0, range: low...max(high, low + 1), timeZone: model.timeZone)
            }
        }
    }

    // MARK: Keys and footer

    private var keys: some View {
        HStack(spacing: 6) {
            if model.canRefresh {
                Button(action: actions.refresh) { label("Refresh", key: "R") }
                    .buttonStyle(PillButtonStyle(hint: true))
                    .focusable(false)
                    .help("Ask MET again · R")
            }
            Button(action: actions.choosePlace) { label("Place", key: "L") }
                .buttonStyle(PillButtonStyle(hint: true))
                .focusable(false)
                .help("Change place · L")
            Spacer(minLength: 0)
            Button(action: actions.openSettings) { label("Settings", key: ",") }
                .buttonStyle(PillButtonStyle(hint: true))
                .focusable(false)
                .help("Settings · ,")
        }
    }

    private func label(_ text: String, key: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
            KeyHint(key: key)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Link("Weather data © MET Norway", destination: URL(string: "https://www.met.no/en")!)
                .foregroundStyle(Nimbi.Text.dim)
                .help("MET Norway's Locationforecast, CC BY 4.0")
                .focusable(false)
            Spacer(minLength: 0)
            if let fetchedAt = model.fetchedAt {
                Text("Updated \(Clock.moment(fetchedAt, in: .current))")
                    .foregroundStyle(Nimbi.Text.faint)
                    .monospacedDigit()
            }
        }
        .font(look.font(10))
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Nimbi.Line.row).frame(height: 0.5) }
    }
}

/// One day: name, symbol, low, the range bar on a shared scale, high.
struct DayRow: View {
    var day: SkyReport.Day
    var isToday: Bool
    var range: ClosedRange<Double>
    var timeZone: TimeZone
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        let k = look.textScale
        HStack(spacing: 8) {
            Text(name)
                .font(look.font(12.5, .medium))
                .foregroundStyle(Nimbi.Text.strong)
                .frame(width: 40 * k, alignment: .leading)
            Image(systemName: day.symbol?.systemImage ?? "cloud")
                .font(look.font(12.5, .medium))
                .foregroundStyle(Nimbi.Text.strong)
                .frame(width: 18 * k)
            Text(degrees(day.low))
                .foregroundStyle(Nimbi.Text.dim)
                .frame(width: 28 * k, alignment: .trailing)
            RangeBar(low: day.low, high: day.high, range: range)
                .frame(height: 4)
            Text(degrees(day.high))
                .foregroundStyle(Nimbi.Text.message)
                .frame(width: 28 * k, alignment: .leading)
        }
        .font(look.font(12.5))
        .monospacedDigit()
        .frame(minHeight: 26 * k)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var name: String {
        isToday ? "Today" : Clock.formatter("EEE", timeZone).string(from: day.date)
    }

    private var spoken: String {
        let full = isToday ? "Today" : Clock.formatter("EEEE", timeZone).string(from: day.date)
        let sky = day.symbol.map { ", \($0.phrase.lowercased())" } ?? ""
        return "\(full): \(degrees(day.low)) to \(degrees(day.high))\(sky)"
    }

    private func degrees(_ t: Double) -> String { "\(Int(t.rounded()))°" }
}

/// A day's low–high span on the week's scale.
struct RangeBar: View {
    var low: Double
    var high: Double
    var range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let x0 = CGFloat((low - range.lowerBound) / span) * geo.size.width
            let x1 = CGFloat((high - range.lowerBound) / span) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.85)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, x1 - x0))
                    .offset(x: x0)
            }
        }
    }
}
