import AppKit
import NimbiKit
import SkylineCore
import SwiftUI

/// Developer check: `SKYLINE_DEMO=rain Skyline --render <dir>` draws the dropdown's pages for the
/// demo sky into PNGs (at 2x), without opening a window, taking the keyboard or moving the pointer.
@MainActor
enum RenderCommand {
    static func run(into directory: URL) {
        guard Demo.sky != nil else {
            FileHandle.standardError.write(Data("set SKYLINE_DEMO=rain|storm|clear\n".utf8))
            exit(2)
        }
        LookSettings.load()
        let model = SkyModel()
        model.start()
        let state = PanelState()
        let actions = PanelActions(refresh: {}, choosePlace: {}, openSettings: {}, back: {}, choose: { _ in },
                                   about: {}, toggleDetails: {})
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func shot(_ name: String, _ setup: () -> Void) {
            setup()
            let view = DropdownRoot(state: state, model: model, location: model.location,
                                    search: PlaceSearch(location: model.location), notch: NotchWatch(), actions: actions)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            let url = directory.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }
        shot("forecast") { state.page = .forecast; state.selectedDay = 0; state.conditionsStyle = .strip }
        shot("forecast-more") { state.conditionsStyle = .grid }
        shot("day-2") { state.conditionsStyle = .strip; state.selectedDay = 2 }
        shot("settings") { state.selectedDay = 0; state.page = .settings }
    }
}
