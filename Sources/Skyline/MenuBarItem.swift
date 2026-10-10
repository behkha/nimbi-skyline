import AppKit
import Combine
import NimbiKit
import SkylineCore
import SwiftUI

/// The menu bar glyph (DESIGN.md 11.3, option A): the nimbi cloud outline with its eyes cut out,
/// as a template image so macOS tints it, then the temperature. Drizzle marks hang under the
/// cloud only while rain starts within the hour; an amber dot shows only when the mood's
/// urgency is `needsYou` (thunder, storm-force wind or dangerous heat within three hours).
enum MenuBarGlyph {
    static let size = NSSize(width: 18, height: 18)

    static func image(drizzle: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Smaller with drizzle, so the marks fit under it in the same 18 pt.
            let s: CGFloat = drizzle ? 13 : 15
            let origin = CGPoint(x: (size.width - s) / 2, y: drizzle ? 1 : (size.height - s) / 2)
            let cloud = CGMutablePath()
            cloud.addPath(CloudShape().path(in: CGRect(origin: origin, size: CGSize(width: s, height: s))).cgPath)
            // The eyes, looking a touch right, cut out with the even-odd rule.
            let face = CGPoint(x: origin.x + s / 2 + s * 0.08, y: origin.y + s / 2 - s * 0.02)
            for (dx, dy) in [(-s * 0.095, 0), (s * 0.095, s * 0.01)] {
                cloud.addEllipse(in: CGRect(x: face.x + dx - s * 0.07, y: face.y + dy - s * 0.1,
                                            width: s * 0.14, height: s * 0.2))
            }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(cloud)
            context.fillPath(using: .evenOdd)
            if drizzle {
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(1.3)
                context.setLineCap(.round)
                for dx in [4.0, 8.0, 12.0] as [CGFloat] {
                    context.move(to: CGPoint(x: origin.x + dx - 2, y: origin.y + s + 1))
                    context.addLine(to: CGPoint(x: origin.x + dx - 3, y: origin.y + s + 3.4))
                }
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Owns the status item: draws the glyph and temperature from the model, and turns clicks into
/// opening the dropdown (left) or a short menu (right).
@MainActor
final class MenuBarItem: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onClick: (() -> Void)?
    var menu: () -> NSMenu = { NSMenu() }

    private let model: SkyModel
    private let dot = NSView()
    private var bag: Set<AnyCancellable> = []
    private let plain = MenuBarGlyph.image(drizzle: false)
    private let drizzle = MenuBarGlyph.image(drizzle: true)

    init(model: SkyModel) {
        self.model = model
        super.init()
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(Nimbi.State.waiting).cgColor
        dot.layer?.cornerRadius = 2.6
        dot.isHidden = true
        button.addSubview(dot)

        model.$report.combineLatest(model.$mood, model.$place)
            .receive(on: RunLoop.main)
            .sink { [weak self] report, mood, place in self?.draw(report, mood, place) }
            .store(in: &bag)
    }

    private func draw(_ report: SkyReport?, _ mood: SkyMood, _ place: Place?) {
        guard let button = statusItem.button else { return }
        button.image = report?.rain.isSoon == true ? drizzle : plain
        let temperature = report.map { "\(Int($0.current.temperature.rounded()))°" } ?? "–°"
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.attributedTitle = NSAttributedString(string: " " + temperature, attributes: [.font: font])

        let needsYou = mood.urgency == .needsYou
        dot.isHidden = !needsYou
        button.layoutSubtreeIfNeeded()
        if let cell = button.cell {
            let image = cell.imageRect(forBounds: button.bounds)
            let d: CGFloat = 5.2
            let y = button.isFlipped ? image.minY + 0.4 : image.maxY - d - 0.4
            dot.frame = NSRect(x: image.maxX - d + 0.4, y: y, width: d, height: d)
        }

        let headline = report?.headline(timeZone: place?.timeZone ?? .current)
        let line = [place?.name, headline].compactMap { $0 }.joined(separator: " · ")
        button.toolTip = line.isEmpty ? "Skyline" : line
        var spoken = ["Skyline", report == nil ? "no forecast yet" : temperature]
        if !line.isEmpty { spoken.append(line) }
        if needsYou { spoken.append("needs you") }
        button.setAccessibilityLabel(spoken.joined(separator: ", "))
    }

    func highlight(_ on: Bool) { statusItem.button?.highlight(on) }

    /// The button's frame on screen, for hanging the dropdown below it.
    var buttonFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = menu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onClick?()
        }
    }
}
