import AppKit
import SkylineCore

/// Wires the pieces: the sky model, the menu bar glyph, the dropdown and the About window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SkyModel()
    private var item: MenuBarItem!
    private var dropdown: Dropdown!
    private let about = AboutWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LookSettings.load()
        item = MenuBarItem(model: model)
        dropdown = Dropdown(model: model, item: item)
        dropdown.onAbout = { [weak self] in self?.about.show() }
        item.onClick = { [weak self] in self?.dropdown.toggle() }
        item.menu = { [weak self] in self?.shortMenu() ?? NSMenu() }
        model.start()
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
