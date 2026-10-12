import AppKit
import NimbiKit
import SkylineCore

/// Wires the pieces: the sky model, the menu bar glyph, the notch island (when Skyline owns the
/// notch), the dropdown and the About window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SkyModel()
    private var item: MenuBarItem!
    private var dropdown: Dropdown!
    private let about = AboutWindow()
    private var notch: NotchOwnership!
    private var island: SkylineIsland!

    func applicationDidFinishLaunching(_ notification: Notification) {
        LookSettings.load()
        notch = NotchOwnership(appName: "Skyline")
        item = MenuBarItem(model: model)
        dropdown = Dropdown(model: model, item: item, notch: notch)
        island = SkylineIsland(model: model, ownership: notch)
        island.onOpenPanel = { [weak self] page in self?.dropdown.openFromIsland(page) }
        // One Skyline on screen at a time: the island replaces the menu bar glyph while it's shown.
        island.island.onShown = { [weak self] shown in self?.item.statusItem.isVisible = !shown }
        dropdown.island = island.island
        dropdown.onAbout = { [weak self] in self?.about.show() }
        item.onClick = { [weak self] in self?.dropdown.toggle() }
        item.menu = { [weak self] in self?.shortMenu() ?? NSMenu() }
        model.start()
        if Demo.sky != nil, ProcessInfo.processInfo.environment["SKYLINE_DEMO_SHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.dropdown.showForCapture() }
        }
    }

    /// Right-click: the few things worth reaching without opening the dropdown.
    private func shortMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Change Place…") { [weak self] in self?.dropdown.open(.place) })
        menu.addItem(ClosureMenuItem("Settings…") { [weak self] in self?.dropdown.open(.settings) })
        menu.addItem(ClosureMenuItem("About Skyline") { [weak self] in self?.about.show() })
        menu.addItem(.separator())
        let credit = NSMenuItem(title: "Weather data © MET Norway", action: nil, keyEquivalent: "")
        credit.isEnabled = false
        menu.addItem(credit)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Skyline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}
