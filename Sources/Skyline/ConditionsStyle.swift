import Foundation

/// How many facts the now card shows: only what matters (`strip`) or all of them (`grid`),
/// toggled with D and remembered. The names come from the strip and grid of
/// docs/design-choices.md ("Air, sun and UV"), which the two-pane redesign folded into the card.
enum ConditionsStyle: String {
    case strip, grid

    static let key = "ConditionsStyle"

    static var saved: ConditionsStyle {
        UserDefaults.standard.string(forKey: key).flatMap(ConditionsStyle.init(rawValue:)) ?? .strip
    }

    var other: ConditionsStyle { self == .strip ? .grid : .strip }
}
