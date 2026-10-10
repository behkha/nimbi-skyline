import AppKit
import Combine
import SkylineCore

/// Scaffold only: a text status item and the data pipeline (place, forecast, refresh at
/// `Expires`). The chosen menu bar glyph and dropdown (docs/design-choices.md) replace the
/// placeholder item next.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let location = LocationService()
    private let client = METClient()
    private var tracker = SkyMoodTracker()
    private var refreshTask: Task<Void, Never>?
    private var placeWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "–°"
        let menu = NSMenu()
        menu.addItem(withTitle: "Weather data © MET Norway", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Skyline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        placeWatch = location.$place.removeDuplicates().sink { [weak self] place in
            guard let place else { return }
            self?.refresh(for: place)
        }
        location.start()
    }

    private func refresh(for place: Place) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.update(place)
                // Next allowed request: the cache's Expires or the end of a backoff, never sooner.
                let next = await self.client.nextRefresh(for: place.coordinate) ?? Date().addingTimeInterval(600)
                let wait = max(60, next.timeIntervalSinceNow + 5)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func update(_ place: Place) async {
        do {
            let result = try await client.forecast(for: place.coordinate)
            let now = Date()
            let report = SkyReport(forecast: result.forecast, now: now, timeZone: place.timeZone)
            let mood = tracker.update(report, dataAge: now.timeIntervalSince(result.fetchedAt), now: now)
            if let report {
                statusItem.button?.title = "\(Int(report.current.temperature.rounded()))°"
                statusItem.button?.toolTip = "\(place.name) · \(mood.mood)"
            }
        } catch {
            statusItem.button?.toolTip = "Can't reach the sky right now."
        }
    }
}
