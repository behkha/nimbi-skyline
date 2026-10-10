import Foundation
import NimbiKit

/// How loudly a page may ask for attention in the shared island (DESIGN.md 18.4, 18.5).
public enum Urgency: Int, Comparable, Sendable {
    case none, notice, needsYou

    public static func < (a: Urgency, b: Urgency) -> Bool { a.rawValue < b.rawValue }
}

/// The cloud's state for a sky report. The mapping is written down in README.md ("Moods");
/// keep the two in step.
public struct SkyMood: Equatable {
    public var mood: Mood
    public var urgency: Urgency
    /// For `.busy`: how lively the cloud is (NimbiCloud's `working`), from the rain rate, 1…8.
    public var working: Int

    public init(mood: Mood, urgency: Urgency = .none, working: Int = 0) {
        self.mood = mood
        self.urgency = urgency
        self.working = working
    }

    /// Data older than this can't be trusted to say anything about the sky.
    public static let staleAfter: TimeInterval = 3 * 60 * 60

    /// The first matching rule wins:
    /// 1. no report, or data older than 3 h → lonely
    /// 2. thunder, storm-force wind or dangerous heat in the next 3 h → asking, needsYou
    /// 3. rain starts within the hour → busy, notice
    /// 4. raining now → busy
    /// 5. rain just stopped → happy (for `SkyMoodTracker.reliefDuration`)
    /// 6. 30° or more → overheated
    /// 7. sun below the horizon → asleep
    /// 8. otherwise → relaxed
    public static func from(_ report: SkyReport?, dataAge: TimeInterval, justDried: Bool = false) -> SkyMood {
        guard let report, dataAge < staleAfter else { return SkyMood(mood: .lonely) }
        if !report.hazards.isEmpty { return SkyMood(mood: .asking, urgency: .needsYou) }
        switch report.rain {
        case .soon(_, let peak): return SkyMood(mood: .busy, urgency: .notice, working: liveliness(peak))
        case .now(_, let peak): return SkyMood(mood: .busy, working: liveliness(peak))
        case .dry, .later: break
        }
        if justDried { return SkyMood(mood: .happy) }
        if report.isHot { return SkyMood(mood: .overheated) }
        if report.isNight { return SkyMood(mood: .asleep) }
        return SkyMood(mood: .relaxed)
    }

    /// mm/h to droplets: drizzle 1, light rain 2–3, heavy rain up to 8 (DESIGN.md caps busy at 8).
    static func liveliness(_ rate: Double) -> Int {
        max(1, min(8, Int((rate * 2).rounded(.up))))
    }
}

/// Remembers the last report so "rain just stopped" can show a short happy moment, as
/// DESIGN.md 3.3 asks of happy (2.5–3.5 s, then back to the resting mood).
public struct SkyMoodTracker {
    public static let reliefDuration: TimeInterval = 3

    private var wasWet = false
    private var happyUntil: Date?

    public init() {}

    public mutating func update(_ report: SkyReport?, dataAge: TimeInterval, now: Date) -> SkyMood {
        let wetNow = report?.rain.isWetNow ?? false
        if wasWet, !wetNow, report != nil { happyUntil = now.addingTimeInterval(Self.reliefDuration) }
        if report != nil { wasWet = wetNow }
        let justDried = happyUntil.map { now < $0 } ?? false
        if !justDried { happyUntil = nil }
        return SkyMood.from(report, dataAge: dataAge, justDried: justDried)
    }
}
