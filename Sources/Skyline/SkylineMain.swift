import AppKit
import SkylineCore

@main
enum SkylineMain {
    @MainActor
    static func main() {
        // Developer check: `Skyline --fetch <lat> <lon>` prints what Skyline makes of the live
        // forecast and exits before any UI starts.
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--fetch") {
            let values = arguments.dropFirst(i + 1).prefix(2).compactMap(Double.init)
            guard values.count == 2 else {
                FileHandle.standardError.write(Data("usage: Skyline --fetch <lat> <lon>\n".utf8))
                exit(2)
            }
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await FetchCommand.run(Coordinate(latitude: values[0], longitude: values[1]))
                done.signal()
            }
            done.wait()
            exit(0)
        }

        if let i = arguments.firstIndex(of: "--render"), i + 1 < arguments.count {
            _ = NSApplication.shared
            RenderCommand.run(into: URL(fileURLWithPath: arguments[i + 1]))
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
