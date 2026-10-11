import AppKit
import Combine
import NimbiKit
import SkylineCore
import SwiftUI

/// What the island shows and how far it's open.
@MainActor
final class IslandState: ObservableObject {
    enum Mode: Equatable {
        /// Notch plus two wings: the cloud on the left, the glance on the right.
        case closed
        /// The page (DESIGN.md 18.7): cloud, title, subtitle, actions and the twelve bars.
        case open
        /// Skyline's dropdown hangs from it: as wide as the panel, square below.
        case attached
    }

    @Published var mode = Mode.closed
    @Published var notchWidth: CGFloat = 0
    @Published var height: CGFloat = 32
    @Published var attachedWidth: CGFloat = 318

    /// Just room for the cloud and the glance: the closed island sits over the menu bar and
    /// hides the items under it, so it's narrower than 18.7's 336 pt.
    static let wing: CGFloat = 60
    static let openWidth: CGFloat = 580

    var closedWidth: CGFloat { notchWidth > 0 ? notchWidth + 2 * Self.wing : 2 * Self.wing + 8 }

    /// The island's body (ears not included) in a mode.
    func size(_ mode: Mode, textScale: Double) -> CGSize {
        switch mode {
        case .closed: return CGSize(width: closedWidth, height: height)
        case .open:
            // DESIGN.md 18.7's 580 × 222 holds a row of page dots too; one page needs none.
            return CGSize(width: max(closedWidth, Self.openWidth * textScale), height: height + 160 * textScale)
        case .attached: return CGSize(width: max(closedWidth, attachedWidth), height: height)
        }
    }
}

/// Skyline at the notch, phase 1 of DESIGN.md 18.2: drawn only while the user has picked Skyline
/// as the notch's owner (in Settings, or the other app's switch), and gone the moment another
/// nimbi app is picked. One page, so no page dots and no swiping.
@MainActor
final class IslandController: NSObject {
    private let model: SkyModel
    private let notch: NotchWatch
    private let state = IslandState()
    private let window: IslandWindow
    private var bag: Set<AnyCancellable> = []
    private var openTimer: Timer?
    private var closeTimer: Timer?
    private var keyMonitor: Any?
    private var moveMonitors: [Any] = []
    private var hovering = false

    /// Forecast ↩ and Place L: open Skyline's dropdown hanging from the island.
    var onOpenPanel: ((PanelState.Page) -> Void)?

    /// Called with true while the island is on show: the menu bar glyph steps aside meanwhile.
    var onShown: ((Bool) -> Void)?

    init(model: SkyModel, notch: NotchWatch) {
        self.model = model
        self.notch = notch
        window = IslandWindow()
        super.init()

        let actions = IslandActions(
            forecast: { [weak self] in self?.onOpenPanel?(.forecast) },
            place: { [weak self] in self?.onOpenPanel?(.place) }
        )
        let host = TrackingHostingView(rootView: IslandView(state: state, model: model, actions: actions))
        host.onHover = { [weak self] inside in self?.hover(inside) }
        host.onMouseDown = { [weak self] in self?.clicked() }
        window.contentView = host

        notch.$owner.receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &bag)
        NimbiAppearance.shared.$textScale.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }.store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.update() }
            .store(in: &bag)
    }

    var isShown: Bool { window.isVisible }
    var closedWidth: CGFloat { state.closedWidth }

    /// The island's bottom edge and middle on screen, for hanging the dropdown below it.
    var hangPoint: CGPoint? {
        guard isShown, let screen = NSScreen.islandScreen else { return nil }
        return CGPoint(x: screen.notchMidX, y: screen.frame.maxY - state.height)
    }

    private func update() {
        if notch.ownedBySkyline, let screen = NSScreen.islandScreen {
            let (width, height) = screen.notchSize
            state.notchWidth = width
            state.height = height
            place()
            window.orderFrontRegardless()
            watchMoves(true)
            onShown?(true)
        } else {
            setMode(.closed, animated: false)
            window.orderOut(nil)
            watchMoves(false)
            onShown?(false)
        }
    }

    // MARK: Opening and closing

    func attach(width: CGFloat) {
        state.attachedWidth = width
        setMode(.attached)
    }

    func detach() {
        guard state.mode == .attached else { return }
        hovering = pointerInside
        setMode(hovering ? .open : .closed)
    }

    /// Opens after 0.2 s of hover; closes 0.6 s after the pointer has really left (DESIGN.md
    /// 18.6). Enter and exit events only start things: resizing the window rebuilds its tracking
    /// area and sends stray exits, so leaving is judged by where the pointer is.
    private func hover(_ inside: Bool) {
        guard state.mode != .attached else { return }
        if inside, state.mode == .closed {
            openTimer?.invalidate()
            openTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.pointerInside else { return }
                    self.setMode(.open)
                }
            }
        }
    }

    private var pointerInside: Bool { window.frame.contains(NSEvent.mouseLocation) }

    /// A freshly shown island's tracking area doesn't always report the first entry, so pointer
    /// moves over the closed island count as hovering too. Mouse moves need no permission.
    private func watchMoves(_ on: Bool) {
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors = []
        guard on else { return }
        let check: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.mode == .closed, self.openTimer?.isValid != true, self.pointerInside else { return }
                self.hover(true)
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: check) { moveMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { check($0); return $0 }) {
            moveMonitors.append(local)
        }
    }

    /// While open, checks the pointer ten times a second and closes once it has been away 0.6 s.
    private func watchPointer() {
        guard closeTimer == nil else { return }
        var awaySince: Date?
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.hovering = self.pointerInside
                guard self.state.mode == .open else { timer.invalidate(); self.closeTimer = nil; return }
                if self.hovering { awaySince = nil; return }
                let since = awaySince ?? Date()
                awaySince = since
                if Date().timeIntervalSince(since) >= 0.6 {
                    timer.invalidate()
                    self.closeTimer = nil
                    self.setMode(.closed)
                }
            }
        }
    }

    private func clicked() {
        guard state.mode != .attached else { return }
        openTimer?.invalidate()
        if state.mode == .closed { setMode(.open) }
        // A click is an invitation to use the keys.
        window.makeKey()
        startKeys()
    }

    private func setMode(_ mode: IslandState.Mode, animated: Bool = true) {
        guard mode != state.mode else { place(); return }
        let growing = area(mode) > area(state.mode)
        // Grow the window first and the shape inside it, or shrink the shape first and the window after.
        if growing { place(for: mode) }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animated ? (reduce ? .easeOut(duration: 0.15) : (growing ? Nimbi.Motion.islandOpen : Nimbi.Motion.islandClose)) : nil) {
            state.mode = mode
        }
        if mode == .open { watchPointer() } else { stopKeys() }
        if !growing {
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.45 : 0)) { [weak self] in
                guard let self, self.state.mode == mode else { return }
                self.place(for: mode)
            }
        }
    }

    private func area(_ mode: IslandState.Mode) -> CGFloat {
        let s = state.size(mode, textScale: NimbiAppearance.shared.textScale)
        return s.width * s.height
    }

    private func place(for mode: IslandState.Mode? = nil) {
        guard let screen = NSScreen.islandScreen else { return }
        let size = state.size(mode ?? state.mode, textScale: NimbiAppearance.shared.textScale)
        let width = size.width + 2 * IslandShape.defaultEar
        window.setFrame(NSRect(x: (screen.notchMidX - width / 2).rounded(), y: screen.frame.maxY - size.height,
                               width: width, height: size.height), display: true)
    }

    // MARK: Keys

    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 36, 76: self.onOpenPanel?(.forecast); return nil   // return, enter
            case 37: self.onOpenPanel?(.place); return nil          // L
            case 53: self.setMode(.closed); return nil              // esc
            default: return event
            }
        }
    }

    private func stopKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Borderless, above the menu bar, on every space, and never activating Skyline.
final class IslandWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    /// The island sits in the menu bar; don't let AppKit push it down below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view with hover that works while Skyline isn't the active app, and a click hook.
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    var onMouseDown: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onHover?(true) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onHover?(false) }
    override func mouseDown(with event: NSEvent) { onMouseDown?(); super.mouseDown(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct IslandActions {
    var forecast: () -> Void
    var place: () -> Void
}

// MARK: - Views

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var model: SkyModel
    var actions: IslandActions
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        let size = state.size(state.mode, textScale: look.textScale)
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: radius)
                .fill(Color.black)
            if state.mode == .open, let page {
                OpenPage(page: page, model: model, height: state.height, actions: actions)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.08)))
            } else {
                closed
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: size.width + 2 * IslandShape.defaultEar, height: size.height)
        // The page grows with the island; nothing may spill past its edge on the way.
        .clipShape(IslandShape(bottomRadius: radius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var radius: CGFloat {
        switch state.mode {
        case .closed: return 12
        case .open: return 30
        case .attached: return 0
        }
    }

    private var page: IslandPage? {
        model.report.map {
            IslandPage(report: $0, outlook: model.outlook, urgency: model.urgency, timeZone: model.timeZone,
                       note: model.conditions.note)
        }
    }

    /// The closed island: the cloud in the left wing, the glance in the right one.
    private var closed: some View {
        HStack(spacing: 0) {
            NimbiCloud(size: 24, mood: model.mood.mood, working: model.mood.working, followsCursor: false, lively: false)
                .frame(width: 24, height: 24)
                .frame(width: IslandState.wing, alignment: .center)
            Spacer(minLength: state.notchWidth)
            Text(page?.glance ?? "–°")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Nimbi.Text.primary)
                .lineLimit(1)
                .frame(width: IslandState.wing, alignment: .center)
        }
        .padding(.horizontal, IslandShape.defaultEar)
        .frame(height: state.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skyline, \(page?.title ?? "no forecast yet")")
    }
}

/// The open island's page: cloud at 92, the app's name, title, subtitle, actions, and the bars.
private struct OpenPage: View {
    var page: IslandPage
    @ObservedObject var model: SkyModel
    var height: CGFloat
    var actions: IslandActions
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            NimbiCloud(size: 92, mood: model.mood.mood, working: model.mood.working)
                .frame(width: 92, height: 92)
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
            Spacer(minLength: 0)
            IslandBars(bars: page.bars, summary: model.outlook.summary(timeZone: model.timeZone))
                .frame(width: 132)
        }
        .padding(.horizontal, 28)
        .padding(.top, height)
        .frame(maxHeight: .infinity)
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
