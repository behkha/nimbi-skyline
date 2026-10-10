import AppKit
import Combine
import NimbiKit
import SkylineCore

/// Everything the menu bar and the dropdown show: the place, the forecast read for this minute,
/// and the cloud's mood. Fetches only when METClient allows it (at `Expires`, or after a
/// backoff); in between it re-reads the cached forecast every half minute, so "rain within the
/// hour" moves with the clock without asking MET again.
@MainActor
final class SkyModel: ObservableObject {
    @Published private(set) var place: Place?
    @Published private(set) var report: SkyReport?
    @Published private(set) var outlook = HourlyOutlook(hours: [])
    @Published private(set) var mood = SkyMood(mood: .lonely)
    /// When the forecast on show was fetched.
    @Published private(set) var fetchedAt: Date?
    /// The next moment MET may be asked again.
    @Published private(set) var nextRefresh: Date?
    /// True once `nextRefresh` has passed, so R may ask MET again.
    @Published private(set) var canRefresh = false
    @Published private(set) var isFetching = false
    /// Set when the last attempt failed and there's nothing to show instead.
    @Published private(set) var failed = false

    let location: LocationService
    private let client: METClient
    private var forecast: Forecast?
    private var tracker = SkyMoodTracker()
    private var loop: Task<Void, Never>?
    private var ticker: Timer?
    private var bag: Set<AnyCancellable> = []

    init(location: LocationService? = nil, client: METClient = METClient()) {
        self.location = location ?? LocationService()
        self.client = client
    }

    var timeZone: TimeZone { place?.timeZone ?? .current }

    func start() {
        if let demo = Demo.forecast() {
            place = Demo.place
            forecast = demo
            fetchedAt = Date()
            nextRefresh = Date().addingTimeInterval(30 * 60)
            reread()
            return
        }
        location.$place.removeDuplicates().sink { [weak self] place in
            guard let self else { return }
            let moved = place?.coordinate != self.place?.coordinate
            self.place = place
            // A new name for the same spot (the city found after a GPS fix) needs no new forecast.
            guard moved else { return }
            self.forecast = nil
            self.fetchedAt = nil
            self.reread()
            self.restartLoop()
        }.store(in: &bag)
        // A Mac that slept has missed its refresh; the cache decides whether MET is asked.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.restartLoop() }
            .store(in: &bag)
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reread() }
        }
        location.start()
    }

    /// R in the dropdown. Does nothing before `Expires`: MET's terms forbid asking sooner.
    func refresh() {
        guard canRefresh, !isFetching else { return }
        restartLoop()
    }

    private func restartLoop() {
        loop?.cancel()
        guard let place else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetch(place)
                let next = self.nextRefresh ?? Date().addingTimeInterval(600)
                let wait = max(60, next.timeIntervalSinceNow + 5)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func fetch(_ place: Place) async {
        isFetching = true
        canRefresh = false
        defer { isFetching = false }
        do {
            let result = try await client.forecast(for: place.coordinate)
            guard place.coordinate == self.place?.coordinate else { return }
            forecast = result.forecast
            fetchedAt = result.fetchedAt
            failed = false
        } catch {
            failed = forecast == nil
        }
        nextRefresh = await client.nextRefresh(for: place.coordinate)
        reread()
    }

    /// Reads the cached forecast for this moment.
    private func reread() {
        let now = Date()
        let newReport = forecast.flatMap { SkyReport(forecast: $0, now: now, timeZone: timeZone) }
        let age = fetchedAt.map { now.timeIntervalSince($0) } ?? .infinity
        let newMood = tracker.update(newReport, dataAge: age, now: now)
        if newReport != report { report = newReport }
        if newMood != mood { mood = newMood }
        let newOutlook = forecast.map { HourlyOutlook(forecast: $0, now: now) } ?? HourlyOutlook(hours: [])
        if newOutlook != outlook { outlook = newOutlook }
        let allowed = !isFetching && place != nil && (nextRefresh.map { now >= $0 } ?? true)
        if allowed != canRefresh { canRefresh = allowed }
        // "Rain just stopped" is a short happy moment; come back when it's over.
        if newMood.mood == .happy {
            DispatchQueue.main.asyncAfter(deadline: .now() + SkyMoodTracker.reliefDuration + 0.1) { [weak self] in
                self?.reread()
            }
        }
    }
}
