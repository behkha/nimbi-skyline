import AppKit
import Combine
import NimbiKit
import SkylineCore
import SwiftUI

/// Skyline at the notch, phase 1 of DESIGN.md 18.2: NimbiKit's island, drawn only while the user
/// has picked Skyline as the notch's owner (in Settings, or the other app's switch), and gone the
/// moment another nimbi app is picked. One page, so no page dots and no swiping.
@MainActor
final class SkylineIsland {
    let island: NotchIsland
    private var bag: Set<AnyCancellable> = []

    /// Forecast ↩ and Place L: open Skyline's dropdown hanging from the island.
    var onOpenPanel: ((PanelState.Page) -> Void)?

    init(model: SkyModel, ownership: NotchOwnership) {
        var open: (PanelState.Page) -> Void = { _ in }
        let actions = IslandActions(forecast: { open(.forecast) }, place: { open(.place) })
        island = NotchIsland(ownership: ownership,
                             closed: { state in ClosedIsland(state: state, model: model) },
                             open: { _ in OpenIsland(model: model, actions: actions) })
        open = { [weak self] page in self?.onOpenPanel?(page) }
        island.onKey = { [weak self] code in
            switch code {
            case 36, 76: self?.onOpenPanel?(.forecast); return true   // return, enter
            case 37: self?.onOpenPanel?(.place); return true          // L
            default: return false
            }
        }
        // The other apps' islands show Skyline's dot amber while a hazard needs you.
        model.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak model] _ in
            DispatchQueue.main.async {
                guard let self, let model else { return }
                self.island.setNeedsYou(model.urgency == .needsYou)
            }
        }.store(in: &bag)
    }
}

struct IslandActions {
    var forecast: () -> Void
    var place: () -> Void
}

// MARK: - Views

/// The closed island: the cloud in the left wing, the glance in the right one.
private struct ClosedIsland: View {
    @ObservedObject var state: IslandState
    @ObservedObject var model: SkyModel

    var body: some View {
        let page = model.islandPage
        IslandWings(state: state) {
            NimbiCloud(size: 24, mood: model.mood.mood, working: model.mood.working, followsCursor: false, lively: false)
                .frame(width: 24, height: 24)
        } right: {
            Text(page?.glance ?? "–°")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Nimbi.Text.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skyline, \(page?.title ?? "no forecast yet")")
    }
}

/// The open island: the page, once there's a forecast to show.
private struct OpenIsland: View {
    @ObservedObject var model: SkyModel
    var actions: IslandActions

    var body: some View {
        if let page = model.islandPage {
            OpenPage(page: page, model: model, actions: actions)
        }
    }
}

extension SkyModel {
    var islandPage: IslandPage? {
        report.map {
            IslandPage(report: $0, outlook: outlook, urgency: urgency, timeZone: timeZone, note: conditions.note)
        }
    }
}

/// The open island's page: cloud at 92, the app's name, title, subtitle, actions, and the bars.
private struct OpenPage: View {
    var page: IslandPage
    @ObservedObject var model: SkyModel
    var actions: IslandActions
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            NimbiCloud(size: 92, mood: model.mood.mood, working: model.mood.working,
                       weather: model.report?.cloudWeather ?? .none)
                .frame(width: 92, height: 92)
                .islandDrift(.cloud)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("SKYLINE")
                    .font(.system(size: 11 * look.textScale, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Nimbi.Text.faint)
                Text(page.title)
                    .font(look.font(26, .semibold))
                    .foregroundStyle(Nimbi.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(page.subtitle)
                    .font(look.font(13))
                    .foregroundStyle(Nimbi.Text.dim)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    // Primary (white) only when the sky needs you (DESIGN.md 18.4).
                    Button(action: actions.forecast) { label("Forecast", key: "↩", light: page.urgency == .needsYou) }
                        .buttonStyle(PillButtonStyle(light: page.urgency == .needsYou, hint: true))
                        .focusable(false)
                    Button(action: actions.place) { label("Place", key: "L", light: false) }
                        .buttonStyle(PillButtonStyle(hint: true))
                        .focusable(false)
                }
                .padding(.top, 6)
            }
            .islandDrift(.text)
            Spacer(minLength: 0)
            IslandBars(bars: page.bars, summary: model.outlook.summary(timeZone: model.timeZone))
                .frame(width: 132)
                .islandDrift(.text)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
    }

    private func label(_ text: String, key: String, light: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)
            KeyHint(key: key, onLight: light)
        }
    }
}

/// Twelve bars: rain in mm (flat `rain` color, faint stubs for dry hours), or the temperature on
/// a dry day. Axis: now, +6h, +12h.
struct IslandBars: View {
    var bars: IslandPage.Bars
    var summary: String

    var body: some View {
        Canvas { context, size in
            let values: [Double]
            switch bars {
            case .rain(let mm): values = mm
            case .temperature(let t): values = t
            }
            guard !values.isEmpty else { return }
            let slot = size.width / CGFloat(IslandPage.hours)
            let base = size.height - 16, tallest: CGFloat = 50
            for (i, v) in values.enumerated() {
                let h: CGFloat
                let color: Color
                switch bars {
                case .rain(let mm):
                    let top = max(1.4, mm.max() ?? 0)
                    h = v >= 0.1 ? max(3, CGFloat(v / top) * tallest) : 2
                    color = v >= 0.1 ? Nimbi.State.rain : .white.opacity(0.12)
                case .temperature(let t):
                    let low = t.min() ?? 0, high = max((t.max() ?? 1), low + 1)
                    h = 6 + CGFloat((v - low) / (high - low)) * (tallest - 6)
                    color = .white.opacity(0.5)
                }
                let rect = CGRect(x: CGFloat(i) * slot + (slot - 8) / 2, y: base - h, width: 8, height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
            }
            let label = Font.system(size: 9)
            context.draw(Text("now").font(label).foregroundColor(Nimbi.Text.faint),
                         at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
            context.draw(Text("+6h").font(label).foregroundColor(Nimbi.Text.faint),
                         at: CGPoint(x: size.width / 2, y: size.height), anchor: .bottom)
            context.draw(Text("+12h").font(label).foregroundColor(Nimbi.Text.faint),
                         at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
        }
        .frame(height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityAddTraits(.isImage)
    }
}
