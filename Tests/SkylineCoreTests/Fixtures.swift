import Foundation
@testable import SkylineCore

/// Builds MET compact JSON the way api.met.no shapes it, so tests exercise the real decoder.
enum Fixture {
    static let oslo = Coordinate(latitude: 59.9139, longitude: 10.7522)
    /// Saturday 10 Oct 2026, 14:00 UTC.
    static let t0 = Date(timeIntervalSince1970: 1_791_640_800)

    struct Hour {
        var temperature: Double = 12
        var wind: Double = 3
        var symbol = "cloudy"
        var precipitation = 0.0
        /// Extra `instant.details` from the complete product, by MET's key.
        var instant: [String: Double] = [:]
        /// Extra `next_1_hours.details`, by MET's key.
        var details: [String: Double] = [:]
    }

    static func json(hours: [Hour], start: Date = t0, sixHourly: Int = 0,
                     coordinate: Coordinate = oslo) -> Data {
        let iso = ISO8601DateFormatter()
        var series: [String] = []
        for (i, h) in hours.enumerated() {
            series.append(step(time: iso.string(from: start.addingTimeInterval(Double(i) * 3600)), hour: h, key: "next_1_hours"))
        }
        let afterHourly = start.addingTimeInterval(Double(hours.count) * 3600)
        for i in 0..<sixHourly {
            series.append(step(time: iso.string(from: afterHourly.addingTimeInterval(Double(i) * 6 * 3600)),
                               hour: Hour(), key: "next_6_hours"))
        }
        let text = """
        {"type":"Feature","geometry":{"type":"Point","coordinates":[\(coordinate.longitude),\(coordinate.latitude),12]},
         "properties":{"meta":{"updated_at":"\(iso.string(from: start.addingTimeInterval(-1800)))",
           "units":{"air_temperature":"celsius","precipitation_amount":"mm","wind_speed":"m/s"}},
           "timeseries":[\(series.joined(separator: ","))]}}
        """
        return Data(text.utf8)
    }

    private static func step(time: String, hour h: Hour, key: String) -> String {
        let instant = h.instant.map { ",\"\($0.key)\":\($0.value)" }.joined()
        let details = h.details.map { ",\"\($0.key)\":\($0.value)" }.joined()
        let pressure = h.instant["air_pressure_at_sea_level"] == nil ? "\"air_pressure_at_sea_level\":1012.3," : ""
        let cloud = h.instant["cloud_area_fraction"] == nil ? "\"cloud_area_fraction\":80.1," : ""
        return """
        {"time":"\(time)","data":{"instant":{"details":{\(pressure)\(cloud)"air_temperature":\(h.temperature),
          "relative_humidity":71.2,"wind_from_direction":210.4,"wind_speed":\(h.wind)\(instant)}},
          "\(key)":{"summary":{"symbol_code":"\(h.symbol)"},"details":{"precipitation_amount":\(h.precipitation)\(details)}}}}
        """
    }

    static func forecast(_ hours: [Hour], start: Date = t0, coordinate: Coordinate = oslo) -> Forecast {
        try! Forecast.decodeMET(json(hours: hours, start: start, coordinate: coordinate))
    }

    static func dry(_ count: Int = 24) -> [Hour] { Array(repeating: Hour(), count: count) }
}

/// Plays back scripted HTTP answers and records what was asked.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let reply = record(request) else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        return (reply.body, response)
    }

    private func record(_ request: URLRequest) -> Reply? {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}

/// A clock tests can move.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}
