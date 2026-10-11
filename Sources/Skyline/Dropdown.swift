import AppKit
import Combine
import NimbiKit
import SkylineCore
import SwiftUI

/// What the dropdown's pages can ask for.
struct PanelActions {
    var refresh: () -> Void
    var choosePlace: () -> Void
    var openSettings: () -> Void
    var back: () -> Void
    var choose: (Place) -> Void
    var about: () -> Void
    /// D: the conditions strip or the grid.
    var toggleDetails: () -> Void
}

@MainActor
final class PanelState: ObservableObject {
    enum Page { case forecast, place, settings }
    @Published var page = Page.forecast
    /// Hanging flush from the notch island (DESIGN.md 18.9) rather than from the menu bar glyph.
    @Published var hanging = false
    /// While hanging: at least as wide as the island, so the two read as one piece.
    @Published var minWidth: CGFloat = 0
    @Published var conditionsStyle = ConditionsStyle.saved {
        didSet { UserDefaults.standard.set(conditionsStyle.rawValue, forKey: ConditionsStyle.key) }
    }
}

/// Borderless panel that takes keys without making Skyline the active app.
final class DropdownWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true   // the cloud's eyes follow the cursor
    }
}

/// The dropdown under the menu bar glyph: opens on click, closes on esc, a second click or a
/// click anywhere else. Keys are bound to physical key codes (DESIGN.md 2.6).
@MainActor
final class Dropdown: NSObject, NSWindowDelegate {
    private let window = DropdownWindow()
    private let state = PanelState()
    private let model: SkyModel
    private let item: MenuBarItem
    private let search: PlaceSearch
    private let notch: NotchWatch
    /// Set when Skyline owns the notch; the dropdown can then hang from the island.
    weak var island: IslandController?
    private var host: SizeReportingHostingView<AnyView>!
    private var keyMonitor: Any?
    private var closedAt = Date.distantPast
    var onAbout: (() -> Void)?

    init(model: SkyModel, item: MenuBarItem, notch: NotchWatch) {
        self.model = model
        self.item = item
        self.notch = notch
        self.search = PlaceSearch(location: model.location)
        super.init()
        window.delegate = self
        let actions = PanelActions(
            refresh: { [weak self] in self?.model.refresh() },
            choosePlace: { [weak self] in self?.show(.place) },
            openSettings: { [weak self] in self?.show(.settings) },
            back: { [weak self] in self?.back() },
            choose: { [weak self] place in self?.choose(place) },
            about: { [weak self] in self?.close(); self?.onAbout?() },
            toggleDetails: { [weak self] in self?.toggleDetails() }
        )
        host = SizeReportingHostingView(rootView: AnyView(
            DropdownRoot(state: state, model: model, location: model.location, search: search,
                         notch: notch, actions: actions)
        ))
        host.onFittingSizeChange = { [weak self] in self?.place() }
        window.contentView = host
    }

    var isOpen: Bool { window.isVisible }

    func toggle() {
        if isOpen { close(); return }
        // The click that closed the panel (by taking key away) shouldn't open it again.
        guard Date().timeIntervalSince(closedAt) > 0.25 else { return }
        open(.forecast)
    }

    func open(_ page: PanelState.Page) {
        hang(false)
        state.page = page
        if page == .place { search.reset() }
        place()
        window.makeKeyAndOrderFront(nil)
        item.highlight(true)
        startKeys()
    }

    /// Opens under the notch island, flush with it.
    func openFromIsland(_ page: PanelState.Page) {
        guard let island, island.isShown else { open(page); return }
        if isOpen { item.highlight(false) }
        hang(true)
        state.minWidth = island.closedWidth
        state.page = page
        if page == .place { search.reset() }
        place()
        window.makeKeyAndOrderFront(nil)
        startKeys()
    }

    func close() {
        guard isOpen else { return }
        window.orderOut(nil)
        item.highlight(false)
        stopKeys()
        closedAt = Date()
        state.page = .forecast
        hang(false)
    }

    private func hang(_ on: Bool) {
        guard state.hanging != on else { return }
        state.hanging = on
        // PanelBackground turns into the island's flat-topped black body at the notch.
        NimbiAppearance.shared.dock = on ? .notch : .right
        if !on { island?.detach() }
    }

    private func show(_ page: PanelState.Page) {
        if page == .place { search.reset() }
        withAnimation(Nimbi.Motion.swap) { state.page = page }
    }

    private func toggleDetails() {
        withAnimation(Nimbi.Motion.swap) { state.conditionsStyle = state.conditionsStyle.other }
    }

    private func back() {
        if state.page == .forecast { close() } else { show(.forecast) }
    }

    private func choose(_ place: Place) {
        model.location.choose(place)
        show(.forecast)
    }

    /// Hangs the panel from the glyph: centred under it, kept on screen, top fixed as the
    /// content grows or shrinks.
    private func place() {
        if state.hanging, let island, let hang = island.hangPoint {
            let size = host.fittingSize
            let inset: CGFloat = 16
            island.attach(width: size.width - 2 * inset)
            window.setFrame(NSRect(x: (hang.x - size.width / 2).rounded(), y: (hang.y + inset - size.height).rounded(),
                                   width: size.width, height: size.height), display: true)
            return
        }
        guard let button = item.buttonFrame else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(button) } ?? NSScreen.main
        let size = host.fittingSize
        // The shadow's room (floatingPanelShadow): 16 around, 8 more below.
        let inset: CGFloat = 16
        var x = button.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 6 - inset), visible.maxX - 6 - size.width + inset)
        }
        let top = button.minY - 4 + inset
        window.setFrame(NSRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height),
                        display: true)
    }

    // MARK: Keys

    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func stopKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private enum Key {
        static let r: UInt16 = 15, l: UInt16 = 37, comma: UInt16 = 43, q: UInt16 = 12, d: UInt16 = 2
        static let esc: UInt16 = 53, down: UInt16 = 125, up: UInt16 = 126
    }

    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods == .command, event.keyCode == Key.q { NSApp.terminate(nil); return true }
        guard mods.isEmpty else { return false }
        if event.keyCode == Key.esc { back(); return true }
        switch state.page {
        case .place:
            // The search field takes everything else; arrows move the highlighted city.
            if event.keyCode == Key.down { search.move(1); return true }
            if event.keyCode == Key.up { search.move(-1); return true }
            return false
        case .forecast, .settings:
            switch event.keyCode {
            case Key.r where state.page == .forecast: model.refresh(); return true
            case Key.d where state.page == .forecast: toggleDetails(); return true
            case Key.l: show(.place); return true
            case Key.comma: show(.settings); return true
            default: return false
            }
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) { close() }
}

struct DropdownRoot: View {
    @ObservedObject var state: PanelState
    var model: SkyModel
    var location: LocationService
    var search: PlaceSearch
    var notch: NotchWatch
    var actions: PanelActions
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        page
            .frame(minWidth: state.hanging ? state.minWidth : nil)
            .background(PanelBackground(cornerRadius: Nimbi.Radius.panel))
            .clipShape(clip)
            .floatingPanelShadow()
            .environment(\.hangsFromPill, state.hanging)
            .environment(\.colorScheme, .dark)
            .fixedSize()
    }

    private var clip: AnyShape {
        state.hanging ? AnyShape(IslandBody(radius: Nimbi.Radius.panel + 4))
            : AnyShape(RoundedRectangle(cornerRadius: Nimbi.Radius.panel, style: .continuous))
    }

    @ViewBuilder private var page: some View {
        switch state.page {
        case .forecast: ForecastView(model: model, location: location, style: state.conditionsStyle, actions: actions)
        case .place: PlacePicker(location: location, search: search, actions: actions)
        case .settings: SettingsView(location: location, model: model, panel: state, notch: notch, actions: actions)
        }
    }
}
