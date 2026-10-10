import AppKit
import SkylineCore

/// Wires the pieces: the sky model and the menu bar glyph.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SkyModel()
    private var item: MenuBarItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        LookSettings.load()
        item = MenuBarItem(model: model)
        item.menu = {
            let menu = NSMenu()
            menu.addItem(withTitle: "Weather data © MET Norway", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Skyline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            return menu
        }
        model.start()
    }
}
