import Foundation

/// A cached MET response: the raw body plus the headers that say when to ask again.
public struct CachedForecast: Codable, Equatable, Sendable {
    public var body: Data
    public var expires: Date
    /// MET's `Last-Modified`, kept as sent so `If-Modified-Since` echoes it exactly.
    public var lastModified: String?
    public var fetchedAt: Date

    public init(body: Data, expires: Date, lastModified: String?, fetchedAt: Date) {
        self.body = body
        self.expires = expires
        self.lastModified = lastModified
        self.fetchedAt = fetchedAt
    }
}

public protocol ForecastStore: Sendable {
    func load(_ key: String) -> CachedForecast?
    func save(_ entry: CachedForecast, for key: String)
}

/// One JSON file per coordinate in `~/Library/Caches/app.nimbi.skyline/forecasts`. Survives
/// relaunches, so a restart never re-asks MET before `Expires`.
public final class DiskForecastStore: ForecastStore, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.nimbi.skyline/forecasts", isDirectory: true)
    }

    private func file(_ key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    public func load(_ key: String) -> CachedForecast? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(CachedForecast.self, from: data)
    }

    public func save(_ entry: CachedForecast, for key: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: file(key), options: .atomic)
        }
    }
}

/// For tests and previews.
public final class MemoryForecastStore: ForecastStore, @unchecked Sendable {
    private var entries: [String: CachedForecast] = [:]
    private let lock = NSLock()

    public init(_ entries: [String: CachedForecast] = [:]) { self.entries = entries }

    public func load(_ key: String) -> CachedForecast? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    public func save(_ entry: CachedForecast, for key: String) {
        lock.lock(); defer { lock.unlock() }
        entries[key] = entry
    }
}
