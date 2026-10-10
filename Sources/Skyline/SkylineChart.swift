import NimbiKit
import SkylineCore
import SwiftUI

/// The next 24 hours as a skyline: rain bars (mm per hour) rise from the baseline under the
/// temperature line, with axis labels every six hours. VoiceOver reads one sentence instead.
struct SkylineChart: View {
    var outlook: HourlyOutlook
    var timeZone: TimeZone
    @ObservedObject private var look = NimbiAppearance.shared

    /// Slots on the axis. Always 24, so an hour is the same width whatever the data covers.
    private let slots = 24

    var body: some View {
        let summary = outlook.summary(timeZone: timeZone)
        Canvas { context, size in draw(in: &context, size: size) }
            .frame(height: 112 * look.textScale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityAddTraits(.isImage)
            .help(summary)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let hours = outlook.hours
        guard !hours.isEmpty else { return }
        let scale = look.textScale
        let width = size.width
        let slot = width / CGFloat(slots)
        let top = 17 * scale, band = 38 * scale
        let base = size.height - 22 * scale
        let barMax = 34 * scale

        // Grid every six hours, and the baseline.
        for g in stride(from: 0, to: slots, by: 6) {
            var line = Path()
            line.move(to: CGPoint(x: CGFloat(g) * slot + 0.5, y: top - 8))
            line.addLine(to: CGPoint(x: CGFloat(g) * slot + 0.5, y: base))
            context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: base + 0.5))
        baseline.addLine(to: CGPoint(x: width, y: base + 0.5))
        context.stroke(baseline, with: .color(.white.opacity(0.12)), lineWidth: 1)

        // Rain: the skyline. 2 mm in an hour fills the bar; heavier rain stretches the scale.
        let wettest = outlook.wettest
        let rainTop = max(2, wettest?.precipitation ?? 0)
        for (i, hour) in hours.enumerated() where hour.precipitation >= 0.1 {
            let h = max(2, CGFloat(hour.precipitation / rainTop) * barMax)
            let rect = CGRect(x: CGFloat(i) * slot + 1.5, y: base - h, width: max(1, slot - 3), height: h)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color.rain.opacity(0.85)))
        }

        // Temperature: at least a 6° span, so a flat day reads flat.
        let temps = hours.map(\.temperature)
        var low = temps.min()!, high = temps.max()!
        if high - low < 6 { let mid = (high + low) / 2; low = mid - 3; high = mid + 3 }
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: CGFloat(i) * slot + slot / 2, y: top + CGFloat((high - temps[i]) / (high - low)) * band)
        }
        var line = Path()
        line.move(to: point(0))
        for i in 1..<hours.count { line.addLine(to: point(i)) }
        context.stroke(line, with: .color(Nimbi.Text.strong),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        let now = point(0)
        context.fill(Path(ellipseIn: CGRect(x: now.x - 3, y: now.y - 3, width: 6, height: 6)), with: .color(.white))

        let small = look.font(9.5)
        context.draw(Text(degrees(temps[0])).font(look.font(9.5, .semibold)).foregroundColor(.white),
                     at: CGPoint(x: now.x + 6, y: now.y - 4), anchor: .bottomLeading)
        if let warmest = outlook.warmest, let i = hours.firstIndex(of: warmest), i > 1 {
            context.draw(Text(degrees(warmest.temperature)).font(small).foregroundColor(Nimbi.Text.dim),
                         at: clamped(CGPoint(x: point(i).x, y: point(i).y - 4), width: width), anchor: .bottom)
        }
        if let coldest = outlook.coldest, let i = hours.firstIndex(of: coldest), i > 1 {
            context.draw(Text(degrees(coldest.temperature)).font(small).foregroundColor(Nimbi.Text.dim),
                         at: clamped(CGPoint(x: point(i).x, y: point(i).y + 4), width: width), anchor: .top)
        }
        if let wettest, let i = hours.firstIndex(of: wettest) {
            let h = max(2, CGFloat(wettest.precipitation / rainTop) * barMax)
            context.draw(Text(String(format: "%.1f mm", wettest.precipitation)).font(look.font(9)).foregroundColor(.rain),
                         at: clamped(CGPoint(x: CGFloat(i) * slot + slot / 2, y: base - h - 3), width: width),
                         anchor: .bottom)
        }

        // Hours along the bottom: now, then every six hours, then the end of the day ahead.
        let labelY = base + 5 * scale
        context.draw(Text("Now").font(small).foregroundColor(Nimbi.Text.faint),
                     at: CGPoint(x: 1, y: labelY), anchor: .topLeading)
        let hourFormat = Clock.formatter("HH", timeZone)
        let start = hours[0].time
        for g in stride(from: 6, to: slots, by: 6) {
            let label = hourFormat.string(from: start.addingTimeInterval(Double(g) * 3600))
            context.draw(Text(label).font(small).foregroundColor(Nimbi.Text.faint),
                         at: CGPoint(x: CGFloat(g) * slot, y: labelY), anchor: .top)
        }
        context.draw(Text(hourFormat.string(from: start.addingTimeInterval(Double(slots) * 3600)))
                        .font(small).foregroundColor(Nimbi.Text.faint),
                     at: CGPoint(x: width, y: labelY), anchor: .topTrailing)
    }

    /// Keeps a centred label from running off either end.
    private func clamped(_ p: CGPoint, width: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, 14), width - 14), y: p.y)
    }

    private func degrees(_ t: Double) -> String { "\(Int(t.rounded()))°" }
}
